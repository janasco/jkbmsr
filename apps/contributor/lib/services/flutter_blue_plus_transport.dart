import 'dart:async';

import 'package:bms_core/bms_core.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_transport.dart';

/// `flutter_blue_plus` implementation of [BleTransport].
///
/// Deliberately thin: it scans, connects, binds the JK-BMS GATT
/// notify/write characteristics and streams raw notification bytes. All frame
/// decoding and capture logic lives in `CaptureService` + `bms_core`, so the
/// subtle part is unit-tested without this file.
class FlutterBluePlusTransport implements BleTransport {
  // JK-BMS GATT. 0xFFE0/0xFFE1 is the classic JK-BMS BLE-UART bridge;
  // 0xFF00/0xFF02/0xFF01 is the JK02 triad. Both are JK-only in the JKBMSR
  // GATT map (0xFFF0 is Daly/Offgridtec and is never bound here). The service
  // UUIDs themselves are checked in [BleScanResult.looksLikeJk].
  static const String _jkCharFfe1 = '0000ffe1-0000-1000-8000-00805f9b34fb';
  static const String _jkNotifyFf02 = '0000ff02-0000-1000-8000-00805f9b34fb';
  static const String _jkWriteFf01 = '0000ff01-0000-1000-8000-00805f9b34fb';

  @override
  Future<bool> isSupported() => FlutterBluePlus.isSupported;

  @override
  Stream<List<BleScanResult>> scan({
    Duration timeout = const Duration(seconds: 12),
  }) {
    final controller = StreamController<List<BleScanResult>>();
    final discovered = <String, BleScanResult>{};
    StreamSubscription<List<ScanResult>>? sub;

    Future<void> run() async {
      try {
        if (!await FlutterBluePlus.isSupported) {
          await controller.close();
          return;
        }
        sub = FlutterBluePlus.scanResults.listen((results) {
          var changed = false;
          for (final r in results) {
            final name = r.device.platformName.isNotEmpty
                ? r.device.platformName
                : r.advertisementData.advName;
            final candidate = BleScanResult(
              id: r.device.remoteId.str,
              name: name,
              rssi: r.rssi,
              connectable: r.advertisementData.connectable,
              serviceUuids:
                  r.advertisementData.serviceUuids.map((u) => u.str128.toLowerCase()).toList(),
            );
            // Keep only JK-plausible devices: a JK-like name, or a JK GATT
            // service (the name-independent fallback for blank names). This
            // mirrors apps/ble's scanner filter, narrowed to the one brand
            // Contributor supports.
            final isJk = BmsProtocolHelper.detectBrandFromName(name) == BmsBrand.jkbms;
            if (isJk || candidate.looksLikeJk) {
              discovered[candidate.id] = candidate;
              changed = true;
            }
          }
          if (changed) {
            final sorted = discovered.values.toList()
              ..sort((a, b) => b.rssi.compareTo(a.rssi));
            controller.add(List<BleScanResult>.unmodifiable(sorted));
          }
        });

        await FlutterBluePlus.startScan(timeout: timeout);
        await FlutterBluePlus.isScanning.where((scanning) => !scanning).first;
      } catch (e) {
        controller.addError(e);
      } finally {
        await sub?.cancel();
        try {
          await FlutterBluePlus.stopScan();
        } catch (_) {}
        if (!controller.isClosed) await controller.close();
      }
    }

    unawaited(run());
    return controller.stream;
  }

  @override
  Future<BleSession> connect(String deviceId) async {
    final device = BluetoothDevice.fromId(deviceId);
    await device.connect(timeout: const Duration(seconds: 12));
    try {
      final services = await device.discoverServices();

      BluetoothCharacteristic? notify;
      BluetoothCharacteristic? writeChar;
      for (final service in services) {
        for (final c in service.characteristics) {
          final uuid = c.uuid.str128.toLowerCase();
          final canNotify = c.properties.notify || c.properties.indicate;
          final canWrite = c.properties.write || c.properties.writeWithoutResponse;
          if (canNotify && (uuid == _jkCharFfe1 || uuid == _jkNotifyFf02)) {
            notify ??= c;
          } else if (canNotify && notify == null) {
            notify = c;
          }
          if (canWrite && (uuid == _jkCharFfe1 || uuid == _jkWriteFf01)) {
            writeChar ??= c;
          } else if (canWrite && writeChar == null) {
            writeChar = c;
          }
        }
      }

      if (notify == null) {
        throw StateError('No notify characteristic for JK-BMS on $deviceId');
      }
      if (writeChar == null) {
        throw StateError('No write characteristic for JK-BMS on $deviceId');
      }

      // Real JK hardware needs a moment after the CCCD subscription before it
      // reliably negotiates MTU and accepts writes (same ~100ms/150ms cadence
      // apps/ble uses). Failures here are non-fatal.
      await notify.setNotifyValue(true);
      try {
        await Future.delayed(const Duration(milliseconds: 100));
        await device.requestMtu(517);
        await Future.delayed(const Duration(milliseconds: 150));
      } catch (_) {}

      int rssi = 0;
      try {
        rssi = await device.readRssi();
      } catch (_) {}

      return _FlutterBluePlusSession(
        device: device,
        notify: notify,
        writeChar: writeChar,
        deviceName: device.platformName.isNotEmpty ? device.platformName : device.advName,
        rssi: rssi,
        serviceUuids: services.map((s) => s.uuid.str128.toLowerCase()).toList(),
      );
    } catch (e) {
      await device.disconnect();
      rethrow;
    }
  }
}

class _FlutterBluePlusSession implements BleSession {
  _FlutterBluePlusSession({
    required this.device,
    required this.notify,
    required this.writeChar,
    required this.deviceName,
    required this.rssi,
    required this.serviceUuids,
  });

  final BluetoothDevice device;
  final BluetoothCharacteristic notify;
  final BluetoothCharacteristic writeChar;

  @override
  final String deviceName;

  @override
  final int rssi;

  @override
  final List<String> serviceUuids;

  bool _writeWithoutResponse = true;

  @override
  Stream<List<int>> get notifications => notify.onValueReceived;

  @override
  Future<void> write(List<int> data) async {
    try {
      await writeChar.write(data, withoutResponse: _writeWithoutResponse);
    } catch (_) {
      // The GATT write-without-response bit is not a reliable signal of what
      // a UART-passthrough BMS module expects; flip and retry once.
      _writeWithoutResponse = !_writeWithoutResponse;
      await writeChar.write(data, withoutResponse: _writeWithoutResponse);
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      await notify.setNotifyValue(false);
    } catch (_) {}
    await device.disconnect();
  }
}
