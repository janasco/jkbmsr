import 'discovered_gateway.dart';

/// The stages the gateway reports while it is being configured. They map one to
/// one onto the firmware's provisioning state machine, so a stuck step names
/// the thing that is stuck rather than "something went wrong".
enum ProvisioningStage {
  saving,
  restarting,
  joiningNetwork,
  registering,
  done,
}

class ProvisioningRequest {
  const ProvisioningRequest({
    required this.gateway,
    required this.setupCode,
    required this.ssid,
    required this.password,
    required this.timeZone,
  });

  final DiscoveredGateway gateway;
  final String setupCode;
  final String ssid;
  final String password;

  /// A POSIX TZ string, not an IANA name: the ESP32 has no time zone database.
  final String timeZone;
}

/// The seam the BLE transport plugs into. The flow is built against this so the
/// screens can be tested without a radio.
abstract class GatewayProvisioner {
  Stream<ProvisioningStage> provision(ProvisioningRequest request);
}

/// The default until the transport exists.
///
/// It fails loudly and in words rather than producing a fake success: a setup
/// screen that says "Gateway added" while nothing was written is the worst
/// possible outcome for a device the owner is about to mount.
class UnavailableGatewayProvisioner implements GatewayProvisioner {
  const UnavailableGatewayProvisioner();

  @override
  Stream<ProvisioningStage> provision(ProvisioningRequest request) async* {
    yield* Stream<ProvisioningStage>.error(
      StateError(
        'Bluetooth setup is not available in this build yet.',
      ),
    );
  }
}

/// A scripted provisioner for tests.
class FakeGatewayProvisioner implements GatewayProvisioner {
  FakeGatewayProvisioner({
    this.stages = const [
      ProvisioningStage.saving,
      ProvisioningStage.restarting,
      ProvisioningStage.joiningNetwork,
      ProvisioningStage.registering,
      ProvisioningStage.done,
    ],
    this.delay = Duration.zero,
    this.error,
  });

  final List<ProvisioningStage> stages;
  final Duration delay;
  final Object? error;
  ProvisioningRequest? lastRequest;

  @override
  Stream<ProvisioningStage> provision(ProvisioningRequest request) async* {
    lastRequest = request;
    for (final stage in stages) {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      yield stage;
    }
    if (error != null) {
      throw error!;
    }
  }
}
