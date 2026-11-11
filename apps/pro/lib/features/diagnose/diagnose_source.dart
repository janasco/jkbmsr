import '../../models/device.dart';
import '../../models/telemetry.dart';
import '../../services/api_client.dart';

/// The seam between the diagnosis screen and the API, so the screen can be
/// widget-tested with a fake and the loading rules stay in one place.
abstract class DiagnoseSource {
  Future<List<Device>> devices();
  Future<Telemetry?> latestTelemetry(String deviceId);
}

class ApiDiagnoseSource implements DiagnoseSource {
  ApiDiagnoseSource({APIClient? client}) : _client = client ?? APIClient();

  final APIClient _client;

  @override
  Future<List<Device>> devices() => _client.getDevices();

  @override
  Future<Telemetry?> latestTelemetry(String deviceId) async {
    final details = await _client.getDeviceDetails(deviceId);
    return details['telemetry'] as Telemetry?;
  }
}

/// A scripted source for tests.
class FakeDiagnoseSource implements DiagnoseSource {
  FakeDiagnoseSource({this.deviceList = const [], this.telemetry, this.error});

  final List<Device> deviceList;
  final Telemetry? telemetry;
  final Object? error;

  int telemetryCalls = 0;

  @override
  Future<List<Device>> devices() async {
    if (error != null) throw error!;
    return deviceList;
  }

  @override
  Future<Telemetry?> latestTelemetry(String deviceId) async {
    telemetryCalls++;
    if (error != null) throw error!;
    return telemetry;
  }
}
