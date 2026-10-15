import 'dart:async';

import 'package:bms_core/bms_core.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_transport.dart';

/// `flutter_blue_plus` implementation of [BleTransport].
///
/// Deliberately thin: it scans, connects, binds the JK-BMS GATT
/// notify/write characteristics and streams raw notification bytes. All frame
/// decoding and capture logic lives in `CaptureService` + `bms_core`, so the
/// subtle part is unit-tested without this file.
class FlutterBluePlusTransport implements BleTransport {
  /// [adapterState] and [log] are injectable seams for tests: the adapter state
  /// is read before scanning so Bluetooth-off can be reported as a plain message
  /// without waiting for [FlutterBluePlus.startScan] to throw, and [log] records
  /// the raw reason (which is never shown to the user).
  FlutterBluePlusTransport({
    Future<BluetoothAdapterState> Function()? adapterState,
    void Function(String message)? log,
  })  : _adapterState = adapterState ?? _platformAdapterState,
        _log = log ?? debugPrint;

  // JK-BMS GATT. 0xFFE0/0xFFE1 is the classic JK-BMS BLE-UART bridge;
  // 0xFF00/0xFF02/0xFF01 is the JK02 triad. Both are JK-only in the JKBMSR
  // GATT map (0xFFF0 is Daly/Offgridtec and is never bound here). The service
  // UUIDs themselves are checked in [BleScanResult.looksLikeJk].
  static const String _jkCharFfe1 = '0000ffe1-0000-1000-8000-00805f9b34fb';
  static const String _jkNotifyFf02 = '0000ff02-0000-1000-8000-00805f9b34fb';
  static const String _jkWriteFf01 = '0000ff01-0000-1000-8000-00805f9b34fb';

  final Future<BluetoothAdapterState> Function() _adapterState;
  final void Function(String message) _log;

  /// The current adapter state. `adapterState.first` triggers the plugin's own
  /// `getAdapterState` when nothing has listened yet (which is the case here:
  /// Contributor never subscribes to the adapter-state stream), so it returns
  /// the real state rather than the cached `unknown`.
  static Future<BluetoothAdapterState> _platformAdapterState() =>
      FlutterBluePlus.adapterState.first;

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

        // Bluetooth being switched off (or the OS blocking it) is an expected
        // state, not a failure. Report it as a plain, actionable condition
        // *before* scanning, so the UI never sees a raw PlatformException.
        final adapterFailure = _adapterFailure(await _adapterState());
        if (adapterFailure != null) {
          _reportScanFailure(controller, adapterFailure);
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
      } catch (e, st) {
        // The plugin's raw error (and, in particular, the wording it uses for
        // a disabled adapter) is a fallback: classify it into the same friendly
        // kinds the pre-check produces, so no PlatformException reaches the UI.
        _reportScanFailure(controller, classifyScanFailure(e), stackTrace: st);
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

  /// Maps an adapter state the user can act on to a scan failure, or null when
  /// scanning may proceed. `unknown`/`turningOn`/`turningOff` are left to the
  /// scan itself: the exception path classifies whatever it throws.
  static BleScanException? _adapterFailure(BluetoothAdapterState state) {
    switch (state) {
      case BluetoothAdapterState.off:
        return const BleScanException(BleScanFailureKind.bluetoothOff);
      case BluetoothAdapterState.unauthorized:
        return const BleScanException(BleScanFailureKind.permissionDenied);
      case BluetoothAdapterState.unavailable:
        return const BleScanException(BleScanFailureKind.unsupported);
      default:
        return null;
    }
  }

  /// Records the raw reason in the logs and pushes the friendly failure down
  /// the stream. The product shows only the sentence; the cause stays here.
  void _reportScanFailure(
    StreamController<List<BleScanResult>> controller,
    BleScanException failure, {
    StackTrace? stackTrace,
  }) {
    _log('BLE scan failed (${failure.kind.name}): ${failure.cause}'
        '${stackTrace == null ? '' : '\n$stackTrace'}');
    controller.addError(failure, stackTrace);
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
