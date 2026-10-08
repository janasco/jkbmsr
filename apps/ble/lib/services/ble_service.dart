import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/bms_models.dart';
import '../models/bms_parameter.dart';
import '../protocols/bms_protocol.dart';
import 'app_database.dart';
import 'detection_engine.dart';

class BleBmsService {
  static final BleBmsService _instance = BleBmsService._internal();
  factory BleBmsService() => _instance;
  BleBmsService._internal();

  final _db = AppDatabase();
  static const String _lastDeviceIdKey = 'jkbmsr_last_device_id';

  /// Live Bluetooth adapter on/off state, used to show an in-app notice
  /// when Bluetooth is disabled.
  Stream<BluetoothAdapterState> get adapterStateStream => FlutterBluePlus.adapterState;

  final _statusController = StreamController<BmsStatus>.broadcast();
  Stream<BmsStatus> get statusStream => _statusController.stream;

  final _settingsController = StreamController<BmsSettingsSnapshot>.broadcast();
  Stream<BmsSettingsSnapshot> get settingsStream => _settingsController.stream;
  BmsSettingsSnapshot _currentSettings = BmsSettingsSnapshot.empty(BmsBrand.unknown);
  BmsSettingsSnapshot get currentSettings => _currentSettings;

  // Hardware identity decoded from the JK02 device-info frame (type 0x03).
  // Emits null on disconnect so the UI can fall back to its honest empty
  // state rather than showing a stale serial/uptime from the last session.
  final _deviceInfoController = StreamController<BmsModelInfo?>.broadcast();
  Stream<BmsModelInfo?> get deviceInfoStream => _deviceInfoController.stream;
  BmsModelInfo? _currentDeviceInfo;
  BmsModelInfo? get currentDeviceInfo => _currentDeviceInfo;

  // The BMS's own on-board logbook (JK02 frame type 0x05, requested with
  // command 0xA1). Null until the user requests it and it arrives.
  final _logbookController = StreamController<Jk02Logbook?>.broadcast();
  Stream<Jk02Logbook?> get logbookStream => _logbookController.stream;
  Jk02Logbook? _currentLogbook;
  Jk02Logbook? get currentLogbook => _currentLogbook;

  final _devicesController = StreamController<List<BleDeviceInfo>>.broadcast();
  Stream<List<BleDeviceInfo>> get devicesStream => _devicesController.stream;

  final _logController = StreamController<String>.broadcast();
  Stream<String> get logStream => _logController.stream;

  final List<String> _rawLogs = [];
  List<String> get rawLogs => List.unmodifiable(_rawLogs);

  BluetoothDevice? _connectedDevice;
  BluetoothDevice? get connectedDevice => _connectedDevice;

  // ---- Test-only connection overrides ----
  // Widget tests have no BLE stack, so they can never reach the state where a
  // write (and therefore the PIN gate that fronts it) is reachable. These let
  // a test present the UI as "connected to a JK-BMS with live data" without
  // touching real hardware. Production never sets them; every getter falls
  // back to the real connection state when they are null.
  bool? _debugIsConnected;
  BmsBrand? _debugConnectedBrand;
  bool? _debugHasLiveData;

  /// Test-only. Forces the connection-facing getters so widget tests can
  /// exercise the write path without a real BLE stack. Never call from app
  /// code; see [debugResetConnectionState].
  @visibleForTesting
  void debugSetConnectionState({
    bool? isConnected,
    BmsBrand? brand,
    bool? hasLiveData,
  }) {
    _debugIsConnected = isConnected;
    _debugConnectedBrand = brand;
    _debugHasLiveData = hasLiveData;
  }

  /// Test-only: clears any [debugSetConnectionState] override.
  @visibleForTesting
  void debugResetConnectionState() {
    _debugIsConnected = null;
    _debugConnectedBrand = null;
    _debugHasLiveData = null;
  }

  bool get isConnected => _debugIsConnected ?? (_connectedDevice != null);

  BmsBrand _connectedBrand = BmsBrand.unknown;
  BmsBrand get connectedBrand => _debugConnectedBrand ?? _connectedBrand;

  BluetoothCharacteristic? _writeCharacteristic;
  bool _writeWithoutResponse = false;
  BluetoothCharacteristic? _notifyCharacteristic;

  // Real hardware routinely exposes several GATT services beyond the BMS's
  // own one — Device Information, Battery, a vendor's TI-stack service,
  // etc. Blindly grabbing the first/last notify-or-write characteristic
  // found across *every* service on the device (the old behavior) can
  // silently bind to something like "Device Name" (0x2A00) instead of the
  // actual BMS characteristic — confirmed on real hardware via diagnostic
  // logs showing exactly that happening. This table lets discovery target
  // the right service/characteristic directly, per brand.
  static const Map<BmsBrand, (String service, String? notifyChar, String? writeChar)> _brandGatt = {
    BmsBrand.jkbms: (BmsProtocolHelper.jkBmsServiceUuid, BmsProtocolHelper.jkBmsCharUuid, BmsProtocolHelper.jkBmsCharUuid),
    BmsBrand.ant: (BmsProtocolHelper.antServiceUuid, BmsProtocolHelper.antCharUuid, BmsProtocolHelper.antCharUuid),
    BmsBrand.daly: (BmsProtocolHelper.dalyServiceUuid, BmsProtocolHelper.dalyNotifyCharUuid, BmsProtocolHelper.dalyCharUuid),
    BmsBrand.jbd: (BmsProtocolHelper.jbdServiceUuid, BmsProtocolHelper.jbdNotifyCharUuid, BmsProtocolHelper.jbdWriteCharUuid),
    BmsBrand.seplos: (BmsProtocolHelper.seplosServiceUuid, BmsProtocolHelper.seplosNotifyCharUuid, BmsProtocolHelper.seplosControlCharUuid),
    BmsBrand.tianpower: (BmsProtocolHelper.tianpowerServiceUuid, BmsProtocolHelper.tianpowerNotifyCharUuid, BmsProtocolHelper.tianpowerControlCharUuid),
    BmsBrand.basen: (BmsProtocolHelper.basenServiceUuid, BmsProtocolHelper.basenNotifyCharUuid, BmsProtocolHelper.basenControlCharUuid),
    BmsBrand.ks: (BmsProtocolHelper.ksServiceUuid, BmsProtocolHelper.ksNotifyCharUuid, BmsProtocolHelper.ksControlCharUuid),
    BmsBrand.topband: (BmsProtocolHelper.topbandServiceUuid, BmsProtocolHelper.topbandNotifyCharUuid, null),
    BmsBrand.lolan: (BmsProtocolHelper.lolanServiceUuid, BmsProtocolHelper.lolanNotifyCharUuid, BmsProtocolHelper.lolanControlCharUuid),
  };
  StreamSubscription? _scanSubscription;
  StreamSubscription? _notifySubscription;
  Timer? _pollTimer;

  // JK02 session state — see _startJkSession. JK hardware audibly beeps
  // once for every register request it accepts (0x96 cell-info read / 0x97
  // device-info read). The official JK app sends each exactly once per
  // connection (2-3 beeps at connect) and then passively receives the
  // auto-streamed cell-info frames — this app now does the same, in syssi's
  // order (0x97 first, then a single 0x96 once the handshake parses).
  // Sending 0x96 every poll tick (the pre-v4.13 behavior) made the BMS beep
  // constantly; polling is now only a fallback for hardware that never
  // auto-streams.
  bool _jkHandshakeComplete = false;
  bool _jkCellStreamSeen = false;
  bool _jkCellInfoRequested = false;
  DateTime? _jkDeviceinfoLastRequestAt;
  Timer? _jkHandshakeTimer;
  Timer? _jkStreamWatchdog;

  // Multi-candidate probe flow: when the device name + discovered GATT
  // services can't identify the brand with certainty (e.g. a shared 0xFF00
  // service could be JBD/Seplos/Tianpower/KS), the app steps through each
  // plausible candidate by sending its probe request and watching for a
  // real telemetry frame that only that brand produces. Confirmed once
  // _hasLiveData and a status frame parse as that candidate.
  List<DetectionCandidate>? _probeCandidates;
  int _probeIndex = 0;
  Timer? _probeTimer;

  // Per-brand fragment-reassembly buffers. BLE notifications arrive in
  // small (~20 byte) chunks; each brand's frame is only complete once
  // enough chunks have accumulated (see docs in bms_protocol.dart).
  final List<int> _jkFrameBuffer = [];
  final List<int> _dalyFrameBuffer = [];
  final List<int> _jbdFrameBuffer = [];
  final List<int> _antFrameBuffer = [];
  final List<int> _seplosFrameBuffer = [];
  final List<int> _tianpowerFrameBuffer = [];
  final List<int> _basenFrameBuffer = [];
  final List<int> _ksFrameBuffer = [];
  final List<int> _topbandFrameBuffer = [];
  final List<int> _lolanFrameBuffer = [];

  // JBD/KS/Lolan split telemetry across two responses (status then a
  // separate cell-voltage frame); each holds the most recent status-
  // derived reading while waiting for the matching cell frame to merge
  // voltages into it.
  BmsStatus? _jbdPendingBasicInfo;
  BmsStatus? _ksPendingStatus;
  BmsStatus? _lolanPendingStatus;

  // Real JK02 hardware won't answer a cell-info (0x96) request until the
  // device-info (0x97) handshake has been sent and its response parsed —
  // that response also reveals whether the pack uses the 24- or 32-cell
  // register layout. Confirmed against jkbmsr-firmware's JkBmsBleClient,
  // which always does this handshake before requesting telemetry.
  bool _jkDeviceInfoReceived = false;
  bool _jkIs32s = false;

  BmsStatus _currentStatus = BmsStatus(
    brand: BmsBrand.unknown,
    modelName: 'BMS Not Connected',
    soc: 0,
    totalVoltage: 0.0,
    currentA: 0.0,
    powerW: 0.0,
    remainingCapacityAh: 0.0,
    nominalCapacityAh: 0.0,
    cycleCount: 0,
    cells: const [],
    mosTemp: 0.0,
    t1Temp: 0.0,
    t2Temp: 0.0,
    balanceCurrentA: 0.0,
    chargeMosEnabled: false,
    dischargeMosEnabled: false,
    balanceEnabled: false,
    alarms: const BmsAlarms(),
    timestamp: DateTime.now(),
  );
  BmsStatus get currentStatus => _currentStatus;

  // True once a real, parsed telemetry frame has been published for the
  // *current* connection. Without this, the UI can't tell "connected but no
  // real frame has ever parsed yet" apart from "connected with live data" —
  // both just look like isConnected == true, and BmsStatus's fields default
  // to demo placeholder values (280Ah capacity, 42 cycles, 38.5°C, etc.)
  // rather than zero, so screens that gate on isConnected alone show those
  // placeholders as if they were live hardware readings.
  bool _hasLiveData = false;
  bool get hasLiveData => _debugHasLiveData ?? _hasLiveData;

  void _addLog(String log) {
    // Defensive: never let a security PIN reach the user-visible (and
    // copyable/shareable) diagnostics log, whatever the caller passed in.
    final safe = log.replaceAll(RegExp(r'PIN:\s*\S+'), 'PIN: [redacted]');
    final entry = "[${DateTime.now().toIso8601String().substring(11, 19)}] $safe";
    _rawLogs.insert(0, entry);
    if (_rawLogs.length > 80) _rawLogs.removeLast();
    _logController.add(entry);
  }

  Future<void> startBleScan() async {
    try {
      _addLog("Starting BLE scan for Bluetooth BMS hardware...");
      if (await FlutterBluePlus.isSupported == false) {
        _addLog("Bluetooth Low Energy is not supported on this device.");
        return;
      }

      final discoveredMap = <String, BleDeviceInfo>{};

      _scanSubscription?.cancel();
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (var r in results) {
          final name = r.device.platformName.isNotEmpty ? r.device.platformName : r.advertisementData.advName;
          final brand = BmsProtocolHelper.detectBrandFromName(name);
          final looksLikeBms = brand == BmsBrand.unknown &&
              BmsProtocolHelper.looksLikeBmsService(r.advertisementData.serviceUuids.map((u) => u.str128));

          if (!discoveredMap.containsKey(r.device.remoteId.str)) {
            _addLog("Found nearby BLE device: '${name.isEmpty ? '(no name)' : name}' (${r.device.remoteId.str}, ${r.rssi} dBm)");
          }

          // Only list devices that either match a known BMS name pattern
          // or advertise a known BMS GATT service UUID — unrelated nearby
          // BLE devices (headphones, phones, etc.) are filtered out. This
          // is deliberately looser than a name-only filter (which hid real
          // hardware with blank/renamed advertised names) but still keeps
          // the picker free of clutter.
          if (brand == BmsBrand.unknown && !looksLikeBms) continue;

          discoveredMap[r.device.remoteId.str] = BleDeviceInfo(
            id: r.device.remoteId.str,
            name: name.isNotEmpty ? name : 'Unnamed device (${r.device.remoteId.str.substring(0, 5)})',
            rssi: r.rssi,
            brand: brand,
            isConnectable: r.advertisementData.connectable,
            looksLikeBms: looksLikeBms,
            serviceUuids: r.advertisementData.serviceUuids
                .map((u) => u.str128.toLowerCase())
                .toSet(),
          );
        }
        final sorted = discoveredMap.values.toList()
          ..sort((a, b) {
            int priority(BleDeviceInfo d) => d.brand != BmsBrand.unknown ? 2 : (d.looksLikeBms ? 1 : 0);
            double confidence(BleDeviceInfo d) =>
                DetectionEngine.bestFor(name: d.name, serviceUuids: d.serviceUuids)?.confidence ?? 0.0;
            final c = confidence(b).compareTo(confidence(a));
            if (c != 0) return c;
            final p = priority(b).compareTo(priority(a));
            if (p != 0) return p;
            return b.rssi.compareTo(a.rssi);
          });
        _devicesController.add(sorted);
      });

      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 12));
      _addLog("BLE scan active across 2.4GHz spectrum.");
    } catch (e) {
      _addLog("BLE Scan error: $e");
    }
  }

  Future<bool> connectDevice(String deviceId) async {
    try {
      _addLog("Connecting to Bluetooth device: $deviceId...");

      final device = BluetoothDevice.fromId(deviceId);
      await device.connect(timeout: const Duration(seconds: 12));
      _connectedDevice = device;
      _connectedBrand = BmsProtocolHelper.detectBrandFromName(device.platformName);
      _addLog("Connected to ${device.platformName}!");

      final services = await device.discoverServices();
      _addLog("Discovered ${services.length} GATT services on hardware");

      final serviceUuids = services.map((s) => s.uuid.str128).toSet();
      final candidates = DetectionEngine.candidatesFor(name: device.platformName, serviceUuids: serviceUuids);

      // A name match is authoritative — real BMS hardware reliably carries
      // its brand in the advertised name, so it short-circuits everything.
      final certain = candidates.where(DetectionEngine.isCertain).toList();
      DetectionCandidate? probingCandidate;
      if (_connectedBrand != BmsBrand.unknown && certain.isNotEmpty) {
        _connectedBrand = certain.first.brand;
      } else if (_connectedBrand == BmsBrand.unknown && candidates.isNotEmpty) {
        // Nothing certain: pick the best candidate. If it's probeable, run
        // the probe flow (send its request, watch for a real telemetry
        // frame); otherwise keep it as the "assumed" brand with a log.
        final top = candidates.first;
        if (top.requiresProbe) {
          probingCandidate = top;
          _connectedBrand = top.brand;
        } else {
          _connectedBrand = top.brand;
          _addLog("Best guess from service UUIDs: ${top.brand.name.toUpperCase()} "
              "(${top.reason}) — not certain, and this brand has no probe "
              "request, so treating it as assumed.");
        }
      } else if (_connectedBrand == BmsBrand.unknown) {
        _connectedBrand = _detectBrandFromServices(services);
        if (_connectedBrand != BmsBrand.unknown) {
          _addLog("Name didn't match a known brand, but GATT service UUID identified this as ${_connectedBrand.name.toUpperCase()}.");
        }
      }

      final bound = await _bindGattForBrand(_connectedBrand, services);
      if (!bound) {
        // Notify fell back to the first available characteristic; probe flow
        // can still proceed since it re-runs binding per candidate.
        _addLog("Warning: could not bind the documented BMS GATT characteristics.");
      }

      // Real hardware needs a moment after notifications are subscribed
      // before it reliably negotiates a larger MTU and accepts writes —
      // the official app explicitly waits ~100ms after the CCCD write ack
      // before requesting MTU, then ~150ms more after the MTU changes
      // before sending its first command.
      try {
        await Future.delayed(const Duration(milliseconds: 100));
        await device.requestMtu(517);
        await Future.delayed(const Duration(milliseconds: 150));
      } catch (_) {}

      _resetConnectionState();

      if (probingCandidate != null && _probeCandidates == null) {
        _startProbing(candidates);
      } else {
        _addLog("Resolved brand: ${_connectedBrand.name.toUpperCase()}");
        _beginBrandPolling(_connectedBrand);
        if (_connectedBrand == BmsBrand.unknown) {
          _addLog("Unrecognized BMS brand — live telemetry isn't available for this device.");
        }
      }

      await _db.setValue(_lastDeviceIdKey, deviceId);

      return true;
    } catch (e) {
      _addLog("Connection failed: $e");
      disconnect();
      return false;
    }
  }

  /// Binds the notify + write characteristics for [brand] from the already-
  /// discovered [services]. Re-runnable per probe candidate (a shared-service
  /// family lists sub-brands that might use a different characteristic).
  Future<bool> _bindGattForBrand(BmsBrand brand, List<BluetoothService> services) async {
    _notifyCharacteristic = null;
    _writeCharacteristic = null;
    final gatt = _brandGatt[brand];
    final targetServiceUuid = gatt?.$1;
    var scanServices = services;
    if (targetServiceUuid != null) {
      final matches = services.where((s) => s.uuid.str128.toLowerCase() == targetServiceUuid).toList();
      if (matches.isNotEmpty) {
        scanServices = matches;
      } else {
        _addLog("Warning: expected BMS service $targetServiceUuid not found on this device — falling back to scanning all services.");
      }
    }

    BluetoothCharacteristic? fallbackNotify;
    BluetoothCharacteristic? fallbackWrite;
    for (var s in scanServices) {
      for (var c in s.characteristics) {
        final uuid = c.uuid.str128.toLowerCase();
        if (c.properties.notify || c.properties.indicate) {
          if (gatt?.$2 == uuid) {
            _notifyCharacteristic = c;
          } else {
            fallbackNotify ??= c;
          }
        }
        if (c.properties.write || c.properties.writeWithoutResponse) {
          if (gatt?.$3 == uuid) {
            _writeCharacteristic = c;
          } else {
            fallbackWrite ??= c;
          }
        }
      }
    }
    // Prefer the brand's documented characteristic; fall back to the
    // first notify/write characteristic found in the target service if
    // this specific piece of hardware doesn't expose it under the UUID
    // this app expects.
    _notifyCharacteristic ??= fallbackNotify;
    _writeCharacteristic ??= fallbackWrite;

    if (_notifyCharacteristic != null) {
      await _notifyCharacteristic!.setNotifyValue(true);
      _notifySubscription?.cancel();
      _notifySubscription = _notifyCharacteristic!.onValueReceived.listen(_handleIncomingBleData);
      _addLog("Subscribed to telemetry notifications: ${_notifyCharacteristic!.uuid}");
    } else {
      _addLog("Warning: no notify characteristic found — live telemetry can't be received.");
    }
    if (_writeCharacteristic != null) {
      // The official JK-BMS app always writes with WRITE_TYPE_NO_RESPONSE
      // regardless of what the characteristic's GATT properties
      // advertise (confirmed by decompiling it) — real UART-passthrough
      // BMS modules are frequently unreliable about declaring this bit
      // correctly, and _writeCommand() will flip modes and retry if
      // this guess ever turns out wrong for a given device.
      _writeWithoutResponse = true;
      _addLog(
          "Found command write characteristic: ${_writeCharacteristic!.uuid} (advertises writeWithoutResponse: ${_writeCharacteristic!.properties.writeWithoutResponse})");
    } else {
      _addLog("Warning: no write characteristic found — commands can't be sent to hardware.");
    }
    return _notifyCharacteristic != null && _writeCharacteristic != null;
  }

  /// Clears all per-connection state reused across brand/probe changes.
  void _resetConnectionState() {
    _jkFrameBuffer.clear();
    _dalyFrameBuffer.clear();
    _jbdFrameBuffer.clear();
    _antFrameBuffer.clear();
    _seplosFrameBuffer.clear();
    _tianpowerFrameBuffer.clear();
    _basenFrameBuffer.clear();
    _ksFrameBuffer.clear();
    _topbandFrameBuffer.clear();
    _lolanFrameBuffer.clear();
    _jbdPendingBasicInfo = null;
    _ksPendingStatus = null;
    _lolanPendingStatus = null;
    _jkDeviceInfoReceived = false;
    _jkIs32s = false;
    _jkHandshakeComplete = false;
    _jkCellStreamSeen = false;
    _jkCellInfoRequested = false;
    _jkDeviceinfoLastRequestAt = null;
    _jkHandshakeTimer?.cancel();
    _jkStreamWatchdog?.cancel();
    _hasLiveData = false;
    _currentSettings = BmsSettingsSnapshot.empty(_connectedBrand);
  }

  /// Last-resort brand identification from GATT service UUIDs, used only when
  /// the advertised/platform name matched nothing in the detection engine.
  ///
  /// This deliberately narrows to JK-BMS. 0xFFE0 is the app's primary and
  /// publicly supported service, so an unrecognized-name 0xFFE0 device is
  /// treated as JK-BMS. 0xFFF0 is **not** guessed: it is shared by Daly and
  /// Offgridtec, and neither is a supported product — labelling such a device
  /// as Daly would make the app issue Daly-format reads and writes to
  /// hardware that may not be Daly at all. Returning [BmsBrand.unknown]
  /// surfaces "unsupported" instead of fabricating a match. 0xFF00 is likewise
  /// shared five ways and was never guessed.
  BmsBrand _detectBrandFromServices(List<BluetoothService> services) {
    final uuids = services.map((s) => s.uuid.str128.toLowerCase()).toSet();
    if (uuids.contains(BmsProtocolHelper.jkBmsServiceUuid)) return BmsBrand.jkbms;
    return BmsBrand.unknown;
  }

  Future<String?> getLastDeviceId() => _db.getValue(_lastDeviceIdKey);

  /// Scans briefly for the last device connected in a previous session and
  /// reconnects automatically if it's found nearby. No-op if there is no
  /// remembered device, one is already connected, or nothing turns up
  /// within the scan window.
  Future<void> autoReconnectLastDevice() async {
    if (isConnected) return;
    final lastId = await getLastDeviceId();
    if (lastId == null) return;

    try {
      if (await FlutterBluePlus.isSupported == false) return;
      if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) return;
    } catch (_) {
      return;
    }

    final completer = Completer<void>();
    StreamSubscription? sub;
    sub = FlutterBluePlus.scanResults.listen((results) async {
      final match = results.any((r) => r.device.remoteId.str == lastId);
      if (match && !completer.isCompleted) {
        completer.complete();
        await sub?.cancel();
        try {
          await FlutterBluePlus.stopScan();
        } catch (_) {}
        await connectDevice(lastId);
      }
    });

    try {
      _addLog("Looking for last-connected device $lastId...");
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
    } catch (_) {}

    await Future.any([
      completer.future,
      Future.delayed(const Duration(seconds: 9)),
    ]);
    await sub.cancel();
  }

  Future<bool> _writeCommand(List<int> cmd) async {
    if (_writeCharacteristic == null) return false;
    try {
      await _writeCharacteristic!.write(cmd, withoutResponse: _writeWithoutResponse);
      return true;
    } catch (e) {
      // The GATT "write without response" property bit isn't a reliable
      // signal of what a given BMS module's firmware actually expects —
      // real-world UART-passthrough BLE modules routinely accept one write
      // type but not the one their advertised properties imply. Flip modes
      // and retry once rather than leaving this brand permanently silent.
      final flipped = !_writeWithoutResponse;
      try {
        await _writeCharacteristic!.write(cmd, withoutResponse: flipped);
        _writeWithoutResponse = flipped;
        _addLog("BLE write succeeded after switching to withoutResponse=$flipped.");
        return true;
      } catch (e2) {
        _addLog("BLE write error: $e2");
        debugPrint("BLE write error: $e2");
        return false;
      }
    }
  }

  void _requestLiveFrame() {
    switch (_connectedBrand) {
      case BmsBrand.jkbms:
        // Legacy/fallback path only (hardware that never auto-streamed, see
        // _startJkSession). In the normal handshake session this method must
        // NOT re-send register requests — each one makes the BMS beep. It
        // still sends while probing, where the request IS the probe.
        if (_jkHandshakeComplete || _isProbing) {
          _writeCommand(BmsProtocolHelper.buildJk02Command(
              _jkDeviceInfoReceived ? BmsProtocolHelper.jk02CommandCellInfo : BmsProtocolHelper.jk02CommandDeviceInfo));
        }
        break;
      case BmsBrand.daly:
        _writeCommand(BmsProtocolHelper.buildDalyStatusRequest());
        break;
      case BmsBrand.jbd:
        // CellInfo is requested reactively once BasicInfo comes back (see
        // _handleJbdFragment) — matches the real device's expected flow.
        _writeCommand(BmsProtocolHelper.buildJbdReadCommand(BmsProtocolHelper.jbdCommandBasicInfo));
        break;
      case BmsBrand.ant:
        _writeCommand(BmsProtocolHelper.buildAntStatusRequest());
        break;
      case BmsBrand.seplos:
        _writeCommand(BmsProtocolHelper.buildSeplosStatusRequest());
        break;
      case BmsBrand.tianpower:
        _writeCommand(BmsProtocolHelper.buildTianpowerStatusRequest());
        break;
      case BmsBrand.basen:
        _writeCommand(BmsProtocolHelper.buildBasenStatusRequest());
        break;
      case BmsBrand.ks:
        // Cell voltages requested reactively once the status frame comes
        // back (see _handleKsFragment).
        _writeCommand(BmsProtocolHelper.buildKsStatusRequest());
        break;
      case BmsBrand.lolan:
        // Cell info requested reactively once the status frame comes back
        // (see _handleLolanFragment).
        _writeCommand(BmsProtocolHelper.buildLolanCommand(BmsProtocolHelper.lolanCommandReqStatus));
        break;
      case BmsBrand.topband:
        // Passive/receive-only -- the device streams status automatically
        // once notifications are enabled, no request needed.
        break;
      case BmsBrand.ogt:
      case BmsBrand.unknown:
        break;
    }
  }

  //--------------------------------------------------------------------
  // Brand telemetry loop selection + JK02 silent-stream session
  //--------------------------------------------------------------------

  /// Starts the right telemetry loop for [brand] after connect/probe.
  /// JK-BMS uses the official one-time handshake + passive auto-stream
  /// (silent); every other brand keeps the explicit request polling.
  void _beginBrandPolling(BmsBrand brand) {
    _pollTimer?.cancel();
    if (brand == BmsBrand.unknown) return;
    if (brand == BmsBrand.jkbms) {
      _startJkSession();
    } else {
      _requestLiveFrame();
      _pollTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) => _requestLiveFrame());
    }
  }

  /// Official JK-BMS session flow (per syssi's esphome-jk-bms component):
  /// send 0x97 (device-info) once at connect; once its frame parses, send
  /// 0x96 (cell-info) exactly once. After both, the BMS auto-streams
  /// cell-info frames (0x02) on its own — silently. The poll timer stays
  /// OFF; a watchdog only resumes explicit requests if the stream never
  /// starts or stalls. Re-sending 0x96/0x97 during the session is what makes
  /// the hardware beep constantly (the real cause of the old behavior).
  void _startJkSession() {
    _pollTimer?.cancel();
    _jkHandshakeComplete = false;
    _jkCellStreamSeen = false;
    _jkCellInfoRequested = false;
    _jkHandshakeTimer?.cancel();
    _addLog('JK-BMS: one-time handshake (0x97 device info, then 0x96 cell info) — cell data auto-streams silently afterwards.');
    _writeCommand(BmsProtocolHelper.buildJk02Command(BmsProtocolHelper.jk02CommandDeviceInfo));
    _jkDeviceinfoLastRequestAt = DateTime.now();
    // Safety net for older/quirky firmware that never auto-streams: fall
    // back to explicit polling so telemetry still works — at the cost of
    // the acknowledgment beeps the hardware emits per request.
    _jkHandshakeTimer = Timer(const Duration(seconds: 6), () {
      if (_connectedBrand == BmsBrand.jkbms &&
          isConnected &&
          !_jkCellStreamSeen &&
          !_jkHandshakeComplete) {
        _addLog('JK-BMS: no auto-stream detected — falling back to periodic requests (buzzer will beep per request).');
        _startJkPolling();
      }
    });
  }

  /// Legacy explicit-poll mode for JK hardware that never auto-streamed.
  /// Polls at 3s rather than the generic 1.5s cadence: this path only runs
  /// on hardware that beeps per request, so the slower tick halves the
  /// audible noise at the cost of slightly staler telemetry.
  void _startJkPolling() {
    _jkHandshakeComplete = true;
    _pollTimer?.cancel();
    _requestLiveFrame();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 3000), (_) => _requestLiveFrame());
  }

  /// Feeds the stream watchdog. Called on every received JK cell-info frame
  /// (even ones skipped for parsing) — while frames keep arriving, the
  /// explicit request loop stays asleep. If they stop for 6s, polling
  /// resumes so the dashboard never goes silently stale.
  void _onJkCellFrameReceived() {
    if (_jkHandshakeComplete) return; // legacy mode already polls explicitly
    _jkStreamWatchdog?.cancel();
    _jkStreamWatchdog = Timer(const Duration(seconds: 6), () {
      if (_connectedBrand == BmsBrand.jkbms &&
          isConnected &&
          _jkCellStreamSeen &&
          !_jkHandshakeComplete) {
        _addLog('JK-BMS: cell stream stalled — resuming explicit cell-info requests.');
        _startJkPolling();
      }
    });
  }

  //--------------------------------------------------------------------
  // Live settings: ingest decoded frames into the snapshot and expose the
  // request/write entry points used by the settings editor UI.
  //--------------------------------------------------------------------

  /// Requests the BMS's on-board logbook (JK02 command 0xA1, frame type
  /// 0x05). This is the only brand with a verified BMS-side history; every
  /// other brand returns false and the UI shows an honest empty state.
  Future<bool> requestLogbook() {
    if (_connectedBrand != BmsBrand.jkbms) return Future.value(false);
    return _writeCommand(BmsProtocolHelper.buildJk02LogbookRequest());
  }

  /// Requests a fresh settings dump from the connected BMS. Brands without
  /// a verified settings-frame read are no-ops (they stay editor-disabled).
  void requestSettings() {
    switch (_connectedBrand) {
      case BmsBrand.jkbms:
        // 0x96 is the settings-register read — the hardware beeps once per
        // request, so it's only sent when the user explicitly refreshes the
        // settings editor (same behavior as the official JK app), never as
        // part of the background telemetry loop.
        _writeCommand(
            BmsProtocolHelper.buildJk02Command(BmsProtocolHelper.jk02CommandCellInfo));
        break;
      case BmsBrand.daly:
        _writeCommand(BmsProtocolHelper.buildDalySettingsRequest());
        break;
      case BmsBrand.ks:
        for (final request in BmsProtocolHelper.buildKsSettingsRequests()) {
          _writeCommand(request);
        }
        break;
      case BmsBrand.jbd:
      case BmsBrand.ant:
      case BmsBrand.seplos:
      case BmsBrand.tianpower:
      case BmsBrand.basen:
      case BmsBrand.topband:
      case BmsBrand.lolan:
      case BmsBrand.ogt:
      case BmsBrand.unknown:
        break;
    }
  }

  /// Sends [value] (user units) back to hardware for the connected brand,
  /// using the parameter's verified write register + encode factors. The
  /// frame bytes mirror the syssi/esphome-*-bms write path byte-for-byte.
  Future<bool> writeParameter(BmsParameter parameter, double value) {
    if (_writeCharacteristic == null) return Future.value(false);
    switch (_connectedBrand) {
      case BmsBrand.jkbms:
        final register = parameter.jkWriteRegisterFor(_jkIs32s);
        if (register == null) return Future.value(false);
        final raw = (value / parameter.jkRawFactor).round();
        final frame = BmsProtocolHelper.buildJk02Command(
            register, value: raw, length: parameter.jkWriteLength);
        _addLog("Writing ${parameter.label} = $value → JK02 reg 0x${register.toRadixString(16).toUpperCase().padLeft(2, '0')} (raw $raw).");
        return _writeCommand(frame);
      case BmsBrand.daly:
        final register = parameter.dalyRegister;
        if (register == null) return Future.value(false);
        final raw = (value * parameter.dalyFactor + parameter.dalyOffset)
            .round()
            .clamp(0, 0xFFFF);
        final frame = BmsProtocolHelper.buildDalyFrame(
            BmsProtocolHelper.dalyFunctionWrite, register, raw);
        _addLog("Writing ${parameter.label} = $value → Daly reg 0x${register.toRadixString(16).toUpperCase().padLeft(4, '0')} (raw $raw).");
        return _writeCommand(frame);
      case BmsBrand.ks:
        final register = parameter.ksRegister;
        if (register == null) return Future.value(false);
        final raw = (value * parameter.ksFactor + parameter.ksOffset)
            .round()
            .clamp(0, 0xFFFF);
        final frame = BmsProtocolHelper.buildKsWriteCommand(register, raw);
        _addLog("Writing ${parameter.label} = $value → KS reg 0x${register.toRadixString(16).toUpperCase().padLeft(2, '0')} (raw $raw).");
        return _writeCommand(frame);
      case BmsBrand.jbd:
      case BmsBrand.ant:
      case BmsBrand.seplos:
      case BmsBrand.tianpower:
      case BmsBrand.basen:
      case BmsBrand.topband:
      case BmsBrand.lolan:
      case BmsBrand.ogt:
      case BmsBrand.unknown:
        return Future.value(false);
    }
  }

  void _mergeSettings(Map<String, double> incoming) {
    if (incoming.isEmpty) return;
    _currentSettings = _currentSettings.mergeWith(incoming);
    _settingsController.add(_currentSettings);
  }

  /// Maps a decoded JK02 settings frame (offsets -> raw values) to the
  /// parameter schema's user-unit values and merges them into the snapshot.
  void _ingestJkSettings(Map<int, int> raw) {
    final schema = BmsParameterSchema.forBrand(BmsBrand.jkbms);
    if (schema == null) return;
    final values = <String, double>{};
    for (final p in schema) {
      final frameOffset = p.jkFrameOffset;
      if (frameOffset == null) continue;
      final r = raw[frameOffset];
      if (r == null) continue;
      values[p.id] = r * p.jkRawFactor;
    }
    _mergeSettings(values);
  }

  void _ingestDalySettings(Map<int, int> raw) {
    final schema = BmsParameterSchema.forBrand(BmsBrand.daly);
    if (schema == null) return;
    final values = <String, double>{};
    for (final p in schema) {
      final register = p.dalyRegister;
      if (register == null) continue;
      final r = raw[register];
      if (r == null) continue;
      values[p.id] = (r - p.dalyOffset) / p.dalyFactor;
    }
    _mergeSettings(values);
  }

  void _ingestKsSettings(Map<int, int> raw) {
    final schema = BmsParameterSchema.forBrand(BmsBrand.ks);
    if (schema == null) return;
    final values = <String, double>{};
    for (final p in schema) {
      final register = p.ksRegister;
      if (register == null) continue;
      final r = raw[register];
      if (r == null) continue;
      values[p.id] = (r - p.ksOffset) / p.ksFactor;
    }
    _mergeSettings(values);
  }

  void _handleIncomingBleData(List<int> rawData) {
    if (rawData.isEmpty) return;
    switch (_connectedBrand) {
      case BmsBrand.jkbms:
        _handleJk02Fragment(rawData);
        break;
      case BmsBrand.daly:
        _handleDalyFragment(rawData);
        break;
      case BmsBrand.jbd:
        _handleJbdFragment(rawData);
        break;
      case BmsBrand.ant:
        _handleAntFragment(rawData);
        break;
      case BmsBrand.seplos:
        _handleSeplosFragment(rawData);
        break;
      case BmsBrand.tianpower:
        _handleTianpowerFragment(rawData);
        break;
      case BmsBrand.basen:
        _handleBasenFragment(rawData);
        break;
      case BmsBrand.ks:
        _handleKsFragment(rawData);
        break;
      case BmsBrand.topband:
        _handleTopbandFragment(rawData);
        break;
      case BmsBrand.lolan:
        _handleLolanFragment(rawData);
        break;
      case BmsBrand.ogt:
      case BmsBrand.unknown:
        break;
    }
  }

  void _publish(BmsStatus status) {
    _currentStatus = status;
    _hasLiveData = true;
    _statusController.add(_currentStatus);

    // Probe confirmation: a real telemetry frame that parses as exactly the
    // candidate brand currently being sniffed proves we guessed right —
    // nothing else produces a byte-exact Konfirmed frame for that brand.
    if (_isProbing && status.brand == _probeCandidates![_probeIndex].brand) {
      _confirmProbe();
    }
  }

  //--------------------------------------------------------------------
  // Multi-candidate brand probing
  //--------------------------------------------------------------------

  bool get _isProbing => _probeCandidates != null;

  static const Duration _probeTimeout = Duration(milliseconds: 1800);

  void _startProbing(List<DetectionCandidate> candidates) {
    _probeCandidates = candidates;
    _probeIndex = 0;
    _addLog("Brand not certain from name alone — probing ${candidates.length} candidate(s) in order.");
    _probeStep();
  }

  void _probeStep() {
    _probeTimer?.cancel();
    if (_probeCandidates == null || _probeIndex >= _probeCandidates!.length) {
      return;
    }
    final candidate = _probeCandidates![_probeIndex];
    // Re-bind GATT per candidate in case this family exposes different
    // characteristic UUIDs per sub-brand.
    final services = _connectedDevice?.servicesList;
    if (services != null) {
      _connectedBrand = candidate.brand;
      _bindGattForBrand(candidate.brand, services);
    }
    _addLog("Probe ${_probeIndex + 1}/${_probeCandidates!.length}: ${candidate.brand.name.toUpperCase()} "
        "(${candidate.reason}) — sending its request and listening ${_probeTimeout.inMilliseconds}ms.");
    _requestLiveFrame();
    _probeTimer = Timer(_probeTimeout, _probeNextCandidate);
  }

  void _probeNextCandidate() {
    if (_probeCandidates == null) return;
    _probeIndex++;
    if (_probeIndex >= _probeCandidates!.length) {
      // None responded. Fall back to the strongest theory with a clear log
      // rather than silently staying on the wrong parser.
      final best = _probeCandidates!.first;
      _probeCandidates = null;
      _probeTimer?.cancel();
      _connectedBrand = best.brand;
      _addLog("No candidate answered its probe — keeping ${best.brand.name.toUpperCase()} as assumed brand.");
      _beginBrandPolling(best.brand);
      return;
    }
    _probeStep();
  }

  void _confirmProbe() {
    final confirmed = _probeCandidates![_probeIndex];
    _probeCandidates = null;
    _probeTimer?.cancel();
    _addLog("Probe confirmed: ${confirmed.brand.name.toUpperCase()} "
        "(confidence ${(confirmed.confidence * 100).round()}%).");
    _beginBrandPolling(confirmed.brand);
  }

  void _handleJk02Fragment(List<int> rawData) {
    if (rawData.length >= 4 && rawData[0] == 0x55 && rawData[1] == 0xAA && rawData[2] == 0xEB && rawData[3] == 0x90) {
      _jkFrameBuffer.clear();
    }
    _jkFrameBuffer.addAll(rawData);
    if (_jkFrameBuffer.length < 300) return;

    final frameType = _jkFrameBuffer.length > 4 ? _jkFrameBuffer[4] : null;
    if (frameType == 0x03) {
      final is32s = BmsProtocolHelper.parseJk02DeviceInfoIs32s(_jkFrameBuffer);
      if (is32s != null) {
        _jkIs32s = is32s;
        _jkDeviceInfoReceived = true;
        _addLog("JK-BMS device info received (${is32s ? '32-cell' : '24-cell'} register layout).");
        // Decode the identifying fields (model / hardware / software / serial
        // / manufacturing date / uptime / power-on count) for the
        // device-information panel. Same frame, separate from the layout
        // probe above — a null here must not block the handshake, so it is
        // not treated as a parse failure.
        final info = BmsProtocolHelper.parseJk02DeviceInfoFrame(_jkFrameBuffer);
        if (info != null) {
          _currentDeviceInfo = info;
          _deviceInfoController.add(info);
        }
        // syssi/esphome-jk-bms sends exactly one cell-info (0x96) request
        // after the device-info handshake; the BMS then auto-streams cell
        // frames on its own. This single request is what starts the silent
        // stream — repeatedly polling 0x96 instead is what makes the
        // hardware beep constantly. Guarded so a stray re-parse can't
        // double-send (one extra 0x96 = one extra beep).
        if (!_jkCellInfoRequested) {
          _jkCellInfoRequested = true;
          _writeCommand(BmsProtocolHelper.buildJk02Command(BmsProtocolHelper.jk02CommandCellInfo));
        }
      } else {
        _addLog("JK02 device-info frame CRC/parse check failed.");
      }
    } else if (frameType == 0x02) {
      // Any cell-info frame proves the BMS is streaming — feed the watchdog
      // so the explicit request loop stays asleep (each request = a beep).
      _jkCellStreamSeen = true;
      _onJkCellFrameReceived();
      if (!_jkDeviceInfoReceived) {
        // Layout unknown until device-info arrives — skip rather than
        // guess, matching jkbmsr-firmware's own guard. Re-ask for device
        // info at most every 3s while waiting.
        final now = DateTime.now();
        if (_jkDeviceinfoLastRequestAt == null ||
            now.difference(_jkDeviceinfoLastRequestAt!).inMilliseconds >= 3000) {
          _jkDeviceinfoLastRequestAt = now;
          _writeCommand(BmsProtocolHelper.buildJk02Command(BmsProtocolHelper.jk02CommandDeviceInfo));
        }
        _jkFrameBuffer.clear();
        return;
      }
      final parsed = BmsProtocolHelper.parseJk02CellInfoFrame(_jkFrameBuffer, is32s: _jkIs32s);
      if (parsed != null) {
        _publish(parsed);
      } else {
        _addLog("JK02 cell-info frame CRC/parse check failed.");
      }
    } else if (frameType == 0x01) {
      // Settings frame — arrives as a free response to every 0x96 poll (see
      // requestSettings()), so it rides the normal telemetry stream without
      // needing a separate command on this brand.
      final settings = BmsProtocolHelper.parseJk02SettingsFrame(_jkFrameBuffer);
      if (settings != null) {
        _ingestJkSettings(settings);
      }
    } else if (frameType == 0x05) {
      // Logbook — the BMS's own event history, answered only to an explicit
      // 0xA1 request (see requestLogbook()). It is not part of the normal
      // telemetry stream.
      final logbook = BmsProtocolHelper.parseJk02LogbookFrame(_jkFrameBuffer);
      if (logbook != null) {
        _currentLogbook = logbook;
        _logbookController.add(logbook);
        _addLog("JK-BMS logbook received (${logbook.logCount} entr${logbook.logCount == 1 ? 'y' : 'ies'}).");
      } else {
        _addLog("JK02 logbook frame CRC/parse check failed.");
      }
    }
    _jkFrameBuffer.clear();
  }

  void _handleDalyFragment(List<int> rawData) {
    if (rawData.isNotEmpty && rawData[0] == 0xD2) {
      _dalyFrameBuffer.clear();
    }
    _dalyFrameBuffer.addAll(rawData);
    if (_dalyFrameBuffer.length > 170) {
      _dalyFrameBuffer.clear();
      return;
    }
    final parsed = BmsProtocolHelper.parseDalyStatusFrame(_dalyFrameBuffer);
    if (parsed != null) {
      _publish(parsed);
      _dalyFrameBuffer.clear();
      return;
    }
    // A D2 03 response with an 82-byte payload (0x52) is the settings dump
    // requested via requestSettings(), not a status frame.
    final settings = BmsProtocolHelper.parseDalySettingsFrame(_dalyFrameBuffer);
    if (settings != null) {
      _ingestDalySettings(settings);
      _dalyFrameBuffer.clear();
    }
  }

  void _sendJbdCommand(int commandId) {
    _writeCommand(BmsProtocolHelper.buildJbdReadCommand(commandId));
  }

  void _handleJbdFragment(List<int> rawData) {
    if (rawData.length >= 3 && rawData[0] == 0xDD && rawData[2] == 0x00) {
      _jbdFrameBuffer.clear();
    }
    _jbdFrameBuffer.addAll(rawData);
    if (_jbdFrameBuffer.length > 80) {
      _jbdFrameBuffer.clear();
      return;
    }

    final function = BmsProtocolHelper.jbdResponseFunction(_jbdFrameBuffer);
    if (function == null) return;

    if (function == BmsProtocolHelper.jbdCommandBasicInfo) {
      final parsed = BmsProtocolHelper.parseJbdBasicInfoFrame(_jbdFrameBuffer);
      if (parsed != null) {
        _jbdPendingBasicInfo = parsed;
        _publish(BmsProtocolHelper.withCells(parsed, _currentStatus.cells));
        _sendJbdCommand(BmsProtocolHelper.jbdCommandCellInfo);
      }
    } else if (function == BmsProtocolHelper.jbdCommandCellInfo) {
      final cells = BmsProtocolHelper.parseJbdCellInfoFrame(_jbdFrameBuffer);
      if (cells != null) {
        _publish(BmsProtocolHelper.withCells(_jbdPendingBasicInfo ?? _currentStatus, cells));
      }
    }
    _jbdFrameBuffer.clear();
  }

  void _handleAntFragment(List<int> rawData) {
    if (rawData.length >= 2 && rawData[0] == 0x7E && rawData[1] == 0xA1) {
      _antFrameBuffer.clear();
    }
    _antFrameBuffer.addAll(rawData);
    if (_antFrameBuffer.length > 200) {
      _antFrameBuffer.clear();
      return;
    }
    final parsed = BmsProtocolHelper.parseAntStatusFrame(_antFrameBuffer);
    if (parsed != null) {
      _publish(parsed);
      _antFrameBuffer.clear();
    }
  }

  void _handleSeplosFragment(List<int> rawData) {
    if (rawData.isNotEmpty && rawData[0] == 0x7E) {
      _seplosFrameBuffer.clear();
    }
    _seplosFrameBuffer.addAll(rawData);
    if (_seplosFrameBuffer.length > 200) {
      _seplosFrameBuffer.clear();
      return;
    }
    final parsed = BmsProtocolHelper.parseSeplosSingleMachineFrame(_seplosFrameBuffer);
    if (parsed != null) {
      _publish(parsed);
      _seplosFrameBuffer.clear();
    }
  }

  void _handleTianpowerFragment(List<int> rawData) {
    if (rawData.isNotEmpty && rawData[0] == 0x55) {
      _tianpowerFrameBuffer.clear();
    }
    _tianpowerFrameBuffer.addAll(rawData);
    if (_tianpowerFrameBuffer.length > 20) {
      _tianpowerFrameBuffer.clear();
      return;
    }
    final parsed = BmsProtocolHelper.parseTianpowerStatusFrame(_tianpowerFrameBuffer);
    if (parsed != null) {
      _publish(parsed);
      _tianpowerFrameBuffer.clear();
    } else if (_tianpowerFrameBuffer.length == 20) {
      _tianpowerFrameBuffer.clear();
    }
  }

  void _handleBasenFragment(List<int> rawData) {
    if (rawData.isNotEmpty && (rawData[0] == 0x3A || rawData[0] == 0x3B)) {
      _basenFrameBuffer.clear();
    }
    _basenFrameBuffer.addAll(rawData);
    if (_basenFrameBuffer.length > 50) {
      _basenFrameBuffer.clear();
      return;
    }
    final parsed = BmsProtocolHelper.parseBasenStatusFrame(_basenFrameBuffer);
    if (parsed != null) {
      _publish(parsed);
      _basenFrameBuffer.clear();
    }
  }

  void _handleKsFragment(List<int> rawData) {
    // Upstream treats each notification as one complete frame for this
    // brand (no reassembly) -- mirror that rather than accumulating.
    if (!BmsProtocolHelper.isCompleteKsFrame(rawData)) return;

    final frameType = rawData[1];
    if (frameType == BmsProtocolHelper.ksFrameTypeStatus) {
      final parsed = BmsProtocolHelper.parseKsStatusFrame(rawData);
      if (parsed != null) {
        _ksPendingStatus = parsed;
        _publish(BmsProtocolHelper.withCells(parsed, _currentStatus.cells));
        _writeCommand(BmsProtocolHelper.buildKsCellVoltagesRequest());
      }
    } else if (frameType == BmsProtocolHelper.ksFrameTypeCellVoltages) {
      final cells = BmsProtocolHelper.parseKsCellVoltagesFrame(rawData);
      if (cells != null) {
        _publish(BmsProtocolHelper.withCells(_ksPendingStatus ?? _currentStatus, cells));
      }
    } else if (frameType >= BmsProtocolHelper.ksFrameTypeBasicConfig &&
        frameType <= BmsProtocolHelper.ksFrameTypeCurrentProtection) {
      // One of the four config frames (0x04-0x07) returned for a
      // requestSettings() read — merges into the settings snapshot.
      final settings = BmsProtocolHelper.parseKsSettingsFrame(rawData);
      if (settings != null) {
        _ingestKsSettings(settings);
      }
    }
  }

  void _handleTopbandFragment(List<int> rawData) {
    if (rawData.isNotEmpty &&
        (rawData[0] == 0x5E || rawData[0] == 0x83 || rawData[0] == 0xB0)) {
      _topbandFrameBuffer.clear();
    }
    _topbandFrameBuffer.addAll(rawData);
    if (_topbandFrameBuffer.length > 113) {
      _topbandFrameBuffer.clear();
      return;
    }
    final parsed = BmsProtocolHelper.parseTopbandFrame(_topbandFrameBuffer);
    if (parsed != null) {
      _publish(parsed);
      _topbandFrameBuffer.clear();
    } else if (_topbandFrameBuffer.length == 113) {
      _topbandFrameBuffer.clear();
    }
  }

  void _handleLolanFragment(List<int> rawData) {
    // Lolan's status/cell-info responses aren't length- or CRC-delimited
    // the way the other brands are -- each notification is treated as one
    // complete frame, same as upstream.
    if (!BmsProtocolHelper.isCompleteLolanFrame(rawData)) return;

    if (rawData[0] == BmsProtocolHelper.lolanFrameTypeStatus) {
      final parsed = BmsProtocolHelper.parseLolanStatusFrame(rawData);
      if (parsed != null) {
        _lolanPendingStatus = parsed;
        _publish(BmsProtocolHelper.withCells(parsed, _currentStatus.cells));
        _writeCommand(BmsProtocolHelper.buildLolanCommand(BmsProtocolHelper.lolanCommandReqCellInfo));
      }
    } else if (rawData[0] == BmsProtocolHelper.lolanFrameTypeCellInfo) {
      final cells = BmsProtocolHelper.parseLolanCellInfoFrame(rawData);
      if (cells != null) {
        _publish(BmsProtocolHelper.withCells(_lolanPendingStatus ?? _currentStatus, cells));
      }
    }
  }

  /// [peerMosEnabled] is only consulted for JBD, whose MOS control register
  /// sets charge+discharge together in one write — pass the other switch's
  /// current desired state so it isn't clobbered.
  Future<bool> toggleSwitch(String switchType, bool enable, String pin, {bool? peerMosEnabled}) async {
    _addLog("Sending switch toggle: $switchType -> ${enable ? 'ON' : 'OFF'} (PIN verified)");
    if (_writeCharacteristic == null) {
      _addLog("Error: No write characteristic available. Ensure BMS is connected.");
      return false;
    }

    Uint8List cmd;
    switch (_connectedBrand) {
      case BmsBrand.jkbms:
        final register = BmsProtocolHelper.jk02SwitchRegisters[switchType];
        if (register == null) {
          _addLog("JK-BMS: '$switchType' isn't wired up to a JK02 register yet.");
          return false;
        }
        cmd = BmsProtocolHelper.buildJk02SwitchCommand(register, enable);
        break;
      case BmsBrand.daly:
        final register = switchType == 'charge'
            ? BmsProtocolHelper.dalyRegChargeSwitch
            : switchType == 'discharge'
                ? BmsProtocolHelper.dalyRegDischargeSwitch
                : switchType == 'balance'
                    ? BmsProtocolHelper.dalyRegBalancerSwitch
                    : null;
        if (register == null) {
          _addLog("Daly BMS does not support the '$switchType' switch.");
          return false;
        }
        cmd = BmsProtocolHelper.buildDalySwitchCommand(register, enable);
        break;
      case BmsBrand.jbd:
        if (switchType == 'charge') {
          cmd = BmsProtocolHelper.buildJbdMosControlCommand(chargeEnabled: enable, dischargeEnabled: peerMosEnabled ?? true);
        } else if (switchType == 'discharge') {
          cmd = BmsProtocolHelper.buildJbdMosControlCommand(chargeEnabled: peerMosEnabled ?? true, dischargeEnabled: enable);
        } else {
          _addLog("JBD BMS does not support the '$switchType' switch.");
          return false;
        }
        break;
      case BmsBrand.ant:
        if (switchType == 'charge') {
          cmd = BmsProtocolHelper.buildAntSwitchCommand(enable,
              onRegister: BmsProtocolHelper.antRegChargeOn, offRegister: BmsProtocolHelper.antRegChargeOff);
        } else if (switchType == 'discharge') {
          cmd = BmsProtocolHelper.buildAntSwitchCommand(enable,
              onRegister: BmsProtocolHelper.antRegDischargeOn, offRegister: BmsProtocolHelper.antRegDischargeOff);
        } else if (switchType == 'balance') {
          cmd = BmsProtocolHelper.buildAntSwitchCommand(enable,
              onRegister: BmsProtocolHelper.antRegBalancerOn, offRegister: BmsProtocolHelper.antRegBalancerOff);
        } else {
          _addLog("ANT BMS does not support the '$switchType' switch.");
          return false;
        }
        break;
      case BmsBrand.seplos:
        if (switchType == 'charge') {
          cmd = BmsProtocolHelper.buildSeplosSwitchCommand(BmsProtocolHelper.seplosSwitchBitCharge, enable);
        } else if (switchType == 'discharge') {
          cmd = BmsProtocolHelper.buildSeplosSwitchCommand(BmsProtocolHelper.seplosSwitchBitDischarge, enable);
        } else {
          _addLog("Seplos does not support the '$switchType' switch.");
          return false;
        }
        break;
      case BmsBrand.basen:
        final currentMosfetStatus =
            (_currentStatus.chargeMosEnabled ? 1 : 0) | (_currentStatus.dischargeMosEnabled ? 2 : 0);
        if (switchType == 'charge') {
          cmd = BmsProtocolHelper.buildBasenSwitchCommand(currentMosfetStatus, BmsProtocolHelper.basenBitCharge, enable);
        } else if (switchType == 'discharge') {
          cmd = BmsProtocolHelper.buildBasenSwitchCommand(currentMosfetStatus, BmsProtocolHelper.basenBitDischarge, enable);
        } else {
          _addLog("Basen BMS does not support the '$switchType' switch.");
          return false;
        }
        break;
      case BmsBrand.ks:
        if (switchType == 'charge') {
          cmd = BmsProtocolHelper.buildKsSwitchCommand(BmsProtocolHelper.ksRegCharge, enable);
        } else if (switchType == 'discharge') {
          cmd = BmsProtocolHelper.buildKsSwitchCommand(BmsProtocolHelper.ksRegDischarge, enable);
        } else {
          _addLog("KS48100 BMS does not support the '$switchType' switch.");
          return false;
        }
        break;
      case BmsBrand.lolan:
        if (switchType == 'charge') {
          cmd = BmsProtocolHelper.buildLolanCommand(
              enable ? BmsProtocolHelper.lolanCommandChargeOn : BmsProtocolHelper.lolanCommandChargeOff);
        } else if (switchType == 'discharge') {
          cmd = BmsProtocolHelper.buildLolanCommand(
              enable ? BmsProtocolHelper.lolanCommandDischargeOn : BmsProtocolHelper.lolanCommandDischargeOff);
        } else {
          _addLog("Lolan BMS does not support the '$switchType' switch.");
          return false;
        }
        break;
      case BmsBrand.tianpower:
      case BmsBrand.topband:
      case BmsBrand.ogt:
      case BmsBrand.unknown:
        _addLog("Switch control is not supported for this BMS brand yet.");
        return false;
    }

    try {
      await _writeCharacteristic!.write(cmd, withoutResponse: _writeWithoutResponse);
      _addLog("Switch command packet written to hardware.");
      Future.delayed(const Duration(milliseconds: 300), _requestLiveFrame);
      return true;
    } catch (e) {
      _addLog("Failed to write switch command: $e");
      return false;
    }
  }

  void disconnect() async {
    _pollTimer?.cancel();
    _probeTimer?.cancel();
    _jkHandshakeTimer?.cancel();
    _jkStreamWatchdog?.cancel();
    _probeCandidates = null;
    _notifySubscription?.cancel();
    try {
      await _notifyCharacteristic?.setNotifyValue(false);
    } catch (_) {}
    _notifyCharacteristic = null;
    _writeCharacteristic = null;
    try {
      await _connectedDevice?.disconnect();
    } catch (_) {}
    _connectedDevice = null;
    _connectedBrand = BmsBrand.unknown;
    _hasLiveData = false;
    _currentSettings = BmsSettingsSnapshot.empty(BmsBrand.unknown);
    _settingsController.add(_currentSettings);
    _currentDeviceInfo = null;
    _deviceInfoController.add(null);
    _currentLogbook = null;
    _logbookController.add(null);
    _addLog("Disconnected from BMS hardware.");

    _currentStatus = BmsStatus(
      brand: BmsBrand.unknown,
      modelName: 'BMS Disconnected',
      soc: 0,
      totalVoltage: 0.0,
      currentA: 0.0,
      powerW: 0.0,
      remainingCapacityAh: 0.0,
      nominalCapacityAh: 0.0,
      cycleCount: 0,
      totalCycleCapacityAh: 0.0,
      cells: const [],
      mosTemp: 0.0,
      t1Temp: 0.0,
      t2Temp: 0.0,
      balanceCurrentA: 0.0,
      cellType: '',
      timeEnterSleepSec: 0,
      chargeMosEnabled: false,
      dischargeMosEnabled: false,
      balanceEnabled: false,
      alarms: const BmsAlarms(),
      timestamp: DateTime.now(),
    );
    _statusController.add(_currentStatus);
  }
}
