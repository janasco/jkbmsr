import 'dart:async';
import 'dart:typed_data';

import 'package:bms_core/bms_core.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:universal_ble/universal_ble.dart';

import 'ble_transport.dart';

/// A GATT characteristic reduced to the two properties the JK choice depends
/// on, so the decision can be tested without a radio.
typedef GattCharacteristicView = ({String uuid, bool canNotify, bool canWrite});

/// A GATT service reduced to its UUID and characteristics.
typedef GattServiceView = ({String uuid, List<GattCharacteristicView> characteristics});

/// The chosen notify and write characteristic UUIDs, or null where none fits.
typedef JkCharacteristicChoice = ({String? notify, String? write});

/// Chooses the notify and write characteristics for a JK-BMS.
///
/// Scoping is the whole point. A real device exposes other `notify`/`indicate`
/// characteristics — the Generic Attribute service's Service Changed (0x2A05)
/// is `indicate`, and it is discovered *before* the JK service — so scanning
/// every service binds one the BMS never sends telemetry on, and the capture
/// then fails looking like a range problem. apps/ble scopes to the documented
/// service for exactly this reason.
///
/// Within the scope the documented characteristic wins outright; the first
/// notify/write found is only a fallback for hardware that does not expose the
/// documented UUIDs. The previous version used one `??=` for both, so whichever
/// characteristic happened to be discovered first won and the documented one
/// could never correct it.
JkCharacteristicChoice chooseJkCharacteristics(Iterable<GattServiceView> services) {
  final all = services.toList();
  final scoped = all.where((s) => JkGatt.services.contains(s.uuid)).toList();
  final pool = scoped.isNotEmpty ? scoped : all;

  String? notify;
  String? write;
  String? fallbackNotify;
  String? fallbackWrite;
  for (final service in pool) {
    for (final c in service.characteristics) {
      if (c.canNotify) {
        if (JkGatt.notifyCharacteristics.contains(c.uuid)) {
          notify ??= c.uuid;
        } else {
          fallbackNotify ??= c.uuid;
        }
      }
      if (c.canWrite) {
        if (JkGatt.writeCharacteristics.contains(c.uuid)) {
          write ??= c.uuid;
        } else {
          fallbackWrite ??= c.uuid;
        }
      }
    }
  }
  return (notify: notify ?? fallbackNotify, write: write ?? fallbackWrite);
}

/// The JK-BMS GATT identifiers, named once so the transport and the pure
/// choice function cannot drift apart.
///
/// 0xFFE0/0xFFE1 is the classic JK-BMS BLE-UART bridge; 0xFF00/0xFF02/0xFF01 is
/// the JK02 triad. Both are JK-only in the JKBMSR GATT map (0xFFF0 is
/// Daly/Offgridtec and is never bound here).
abstract final class JkGatt {
  static const String charFfe1 = '0000ffe1-0000-1000-8000-00805f9b34fb';
  static const String notifyFf02 = '0000ff02-0000-1000-8000-00805f9b34fb';
  static const String writeFf01 = '0000ff01-0000-1000-8000-00805f9b34fb';

  static const String serviceClassic = '0000ffe0-0000-1000-8000-00805f9b34fb';
  static const String serviceTriad = '0000ff00-0000-1000-8000-00805f9b34fb';

  static const Set<String> services = {serviceClassic, serviceTriad};
  static const Set<String> notifyCharacteristics = {charFfe1, notifyFf02};
  static const Set<String> writeCharacteristics = {charFfe1, writeFf01};
}

/// `universal_ble` implementation of [BleTransport].
///
/// Deliberately thin: it scans, connects, binds the JK-BMS GATT notify/write
/// characteristics and streams raw notification bytes. All frame decoding and
/// capture logic lives in `CaptureService` + `bms_core`, so the subtle part is
/// unit-tested without this file.
///
/// Replaced the FlutterBluePlus transport on 2026-11-10: that package's 2.x line
/// requires a paid commercial licence for for-profit use, and `universal_ble` is
/// BSD-3. The behaviour below is the behaviour the old transport had, including
/// the ones that were learned the hard way.
class UniversalBleTransport implements BleTransport {
  /// [availability] and [log] are injectable seams for tests: the adapter state
  /// is read before scanning so Bluetooth-off can be reported as a plain message
  /// without waiting for `startScan` to throw, and [log] records the raw reason
  /// (which is never shown to the user).
  UniversalBleTransport({
    Future<AvailabilityState> Function()? availability,
    void Function(String message)? log,
  })  : _availability = availability ?? UniversalBle.getBluetoothAvailabilityState,
        _log = log ?? debugPrint;

  final Future<AvailabilityState> Function() _availability;
  final void Function(String message) _log;

  /// Names seen during the scan, keyed by device id. `connect()` only receives
  /// an id, and the notification stream carries no name, so the scan is the one
  /// place a human-readable name exists.
  final Map<String, String> _names = {};

  @override
  Future<bool> isSupported() async {
    try {
      return await _availability() != AvailabilityState.unsupported;
    } catch (_) {
      return false;
    }
  }

  @override
  Stream<List<BleScanResult>> scan({
    Duration timeout = const Duration(seconds: 12),
  }) {
    final controller = StreamController<List<BleScanResult>>();
    final discovered = <String, BleScanResult>{};
    StreamSubscription<BleDevice>? sub;
    Timer? deadline;
    var finished = false;

    Future<void> finish() async {
      if (finished) return;
      finished = true;
      deadline?.cancel();
      await sub?.cancel();
      try {
        await UniversalBle.stopScan();
      } catch (_) {}
      if (!controller.isClosed) await controller.close();
    }

    Future<void> run() async {
      try {
        // Bluetooth being switched off (or the OS blocking it) is an expected
        // state, not a failure. Report it as a plain, actionable condition
        // *before* scanning, so the UI never sees a raw exception.
        final adapterFailure = _adapterFailure(await _availability());
        if (adapterFailure != null) {
          _reportScanFailure(controller, adapterFailure);
          await finish();
          return;
        }

        sub = UniversalBle.scanStream.listen((device) {
          final name = (device.name?.isNotEmpty ?? false)
              ? device.name!
              : (device.rawName ?? '');
          final candidate = BleScanResult(
            id: device.deviceId,
            name: name,
            rssi: device.rssi ?? 0,
            connectable: device.connectable ?? true,
            serviceUuids: device.services.map((u) => u.toLowerCase()).toList(),
          );
          // Keep only JK-plausible devices: a JK-like name, or a JK GATT
          // service (the name-independent fallback for blank names). This
          // mirrors apps/ble's scanner filter, narrowed to the one brand
          // Contributor supports.
          final isJk = BmsProtocolHelper.detectBrandFromName(name) == BmsBrand.jkbms;
          if (!(isJk || candidate.looksLikeJk)) return;
          discovered[candidate.id] = candidate;
          if (name.isNotEmpty) _names[candidate.id] = name;
          final sorted = discovered.values.toList()
            ..sort((a, b) => b.rssi.compareTo(a.rssi));
          if (!controller.isClosed) controller.add(List<BleScanResult>.unmodifiable(sorted));
        });

        // UniversalBle's startScan has no timeout of its own; the deadline is
        // this transport's contract (the contributors' UI waits for the stream
        // to close).
        deadline = Timer(timeout, () => unawaited(finish()));
        await UniversalBle.startScan();
      } catch (e, st) {
        // The plugin's raw error (and, in particular, the wording it uses for
        // a disabled adapter) is a fallback: classify it into the same friendly
        // kinds the pre-check produces, so no plugin exception reaches the UI.
        _reportScanFailure(controller, classifyScanFailure(e), stackTrace: st);
        await finish();
      }
    }

    unawaited(run());
    return controller.stream;
  }

  /// Maps an availability state the user can act on to a scan failure, or null
  /// when scanning may proceed. `unknown`/`resetting` are left to the scan
  /// itself: the exception path classifies whatever it throws.
  static BleScanException? _adapterFailure(AvailabilityState state) {
    switch (state) {
      case AvailabilityState.poweredOff:
        return const BleScanException(BleScanFailureKind.bluetoothOff);
      case AvailabilityState.unauthorized:
        return const BleScanException(BleScanFailureKind.permissionDenied);
      case AvailabilityState.unsupported:
        return const BleScanException(BleScanFailureKind.unsupported);
      case AvailabilityState.poweredOn:
      case AvailabilityState.unknown:
      case AvailabilityState.resetting:
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
    if (!controller.isClosed) controller.addError(failure, stackTrace);
  }

  @override
  Future<BleSession> connect(String deviceId) async {
    await UniversalBle.connect(deviceId, timeout: const Duration(seconds: 12));
    try {
      final services = await UniversalBle.discoverServices(deviceId);

      final choice = chooseJkCharacteristics([
        for (final s in services)
          (
            uuid: s.uuid.toLowerCase(),
            characteristics: [
              for (final c in s.characteristics)
                (
                  uuid: c.uuid.toLowerCase(),
                  canNotify: c.properties.contains(CharacteristicProperty.notify) ||
                      c.properties.contains(CharacteristicProperty.indicate),
                  canWrite: c.properties.contains(CharacteristicProperty.write) ||
                      c.properties.contains(CharacteristicProperty.writeWithoutResponse),
                ),
            ],
          ),
      ]);

      // A characteristic is addressed through the service that owns it, so the
      // owner is looked up rather than assumed.
      String? notifyService;
      String? writeService;
      for (final s in services) {
        for (final c in s.characteristics) {
          final uuid = c.uuid.toLowerCase();
          if (uuid == choice.notify) notifyService ??= s.uuid.toLowerCase();
          if (uuid == choice.write) writeService ??= s.uuid.toLowerCase();
        }
      }

      final notify = choice.notify;
      final write = choice.write;
      if (notify == null || notifyService == null) {
        throw StateError('No notify characteristic for JK-BMS on $deviceId');
      }
      if (write == null || writeService == null) {
        throw StateError('No write characteristic for JK-BMS on $deviceId');
      }

      // Real JK hardware needs a moment after the CCCD subscription before it
      // reliably negotiates MTU and accepts writes (same ~100ms/150ms cadence
      // apps/ble uses). Failures here are non-fatal.
      await UniversalBle.subscribeNotifications(deviceId, notifyService, notify);
      try {
        await Future.delayed(const Duration(milliseconds: 100));
        await UniversalBle.requestMtu(deviceId, 517);
        await Future.delayed(const Duration(milliseconds: 150));
      } catch (_) {}

      int rssi = 0;
      try {
        rssi = await UniversalBle.readRssi(deviceId);
      } catch (_) {}

      return _UniversalBleSession(
        deviceId: deviceId,
        notifyService: notifyService,
        notifyCharacteristic: notify,
        writeService: writeService,
        writeCharacteristic: write,
        deviceName: _names[deviceId] ?? '',
        rssi: rssi,
        serviceUuids: services.map((s) => s.uuid.toLowerCase()).toList(),
      );
    } catch (e) {
      try {
        await UniversalBle.disconnect(deviceId);
      } catch (_) {}
      rethrow;
    }
  }
}

class _UniversalBleSession implements BleSession {
  _UniversalBleSession({
    required this.deviceId,
    required this.notifyService,
    required this.notifyCharacteristic,
    required this.writeService,
    required this.writeCharacteristic,
    required this.deviceName,
    required this.rssi,
    required this.serviceUuids,
  });

  final String deviceId;
  final String notifyService;
  final String notifyCharacteristic;
  final String writeService;
  final String writeCharacteristic;

  @override
  final String deviceName;

  @override
  final int rssi;

  @override
  final List<String> serviceUuids;

  bool _writeWithoutResponse = true;

  @override
  Stream<List<int>> get notifications =>
      UniversalBle.characteristicValueStream(deviceId, notifyCharacteristic);

  @override
  Future<void> write(List<int> data) async {
    final value = Uint8List.fromList(data);
    try {
      await UniversalBle.write(
        deviceId,
        writeService,
        writeCharacteristic,
        value,
        withoutResponse: _writeWithoutResponse,
      );
    } catch (_) {
      // The GATT write-without-response bit is not a reliable signal of what
      // a UART-passthrough BMS module expects; flip and retry once.
      _writeWithoutResponse = !_writeWithoutResponse;
      await UniversalBle.write(
        deviceId,
        writeService,
        writeCharacteristic,
        value,
        withoutResponse: _writeWithoutResponse,
      );
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      await UniversalBle.unsubscribe(deviceId, notifyService, notifyCharacteristic);
    } catch (_) {}
    try {
      await UniversalBle.disconnect(deviceId);
    } catch (_) {}
  }
}
