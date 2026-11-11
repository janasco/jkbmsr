import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

import 'gateway_provisioner.dart';
import 'provisioning_protocol.dart';

/// Configuring a gateway over BLE.
///
/// The order is the contract: the setup code is written first and the firmware
/// refuses every other write before it, so a phone that connects by accident
/// cannot change a gateway's network settings.
class BleGatewayProvisioner implements GatewayProvisioner {
  const BleGatewayProvisioner({
    this.connectTimeout = const Duration(seconds: 15),
    this.statusTimeout = const Duration(seconds: 90),
  });

  final Duration connectTimeout;

  /// The gateway restarts and rejoins Wi-Fi inside this window, so it is
  /// generous; a shorter one would report a failure that is really "still
  /// working".
  final Duration statusTimeout;

  @override
  Stream<ProvisioningStage> provision(ProvisioningRequest request) async* {
    if (!ProvisioningProtocol.isValidSetupCode(request.setupCode)) {
      throw StateError('The setup code must be six digits.');
    }

    final payload = ProvisioningProtocol.encodePayload(
      ssid: request.ssid,
      password: request.password,
      timeZone: request.timeZone,
      claimToken: request.claimToken,
    );

    yield ProvisioningStage.saving;
    await UniversalBle.connect(request.gateway.id, timeout: connectTimeout);

    final statuses = StreamController<ProvisioningStatus>();
    var finished = false;

    try {
      final services = await UniversalBle.discoverServices(request.gateway.id);
      final hasService = services.any(
        (s) => s.uuid.toLowerCase() == ProvisioningProtocol.service,
      );
      if (!hasService) {
        throw StateError(
          'This gateway does not offer the setup service. It may already be set up.',
        );
      }

      await UniversalBle.subscribeNotifications(
        request.gateway.id,
        ProvisioningProtocol.service,
        ProvisioningProtocol.statusCharacteristic,
      );

      UniversalBle.onValueChange = (value) {
        // universal_ble normalises short UUIDs to their 128-bit form, so the
        // comparison is exact rather than a suffix match.
        if (value.characteristicId.toLowerCase() !=
            ProvisioningProtocol.statusCharacteristic) {
          return;
        }
        if (statuses.isClosed) return;
        statuses.add(
          ProvisioningProtocol.parseStatus(utf8.decode(value.value, allowMalformed: true)),
        );
      };

      await _write(
        request.gateway.id,
        ProvisioningProtocol.setupCharacteristic,
        utf8.encode(request.setupCode),
      );

      for (final chunk in ProvisioningProtocol.chunks(payload)) {
        await _write(
          request.gateway.id,
          ProvisioningProtocol.payloadCharacteristic,
          chunk,
          withoutResponse: true,
        );
      }

      await _write(
        request.gateway.id,
        ProvisioningProtocol.commandCharacteristic,
        utf8.encode(ProvisioningProtocol.commitCommand),
      );

      await for (final status in statuses.stream.timeout(statusTimeout)) {
        switch (status) {
          case ProvisioningStatus.applying:
            yield ProvisioningStage.saving;
            break;
          case ProvisioningStatus.rebooting:
            yield ProvisioningStage.restarting;
            break;
          case ProvisioningStatus.registering:
            yield ProvisioningStage.registering;
            break;
          case ProvisioningStatus.done:
            finished = true;
            yield ProvisioningStage.done;
            return;
          case ProvisioningStatus.failed:
            throw StateError(
              'The gateway rejected the settings. Check the Wi-Fi name and password, then try again.',
            );
          case ProvisioningStatus.advertising:
          case ProvisioningStatus.connected:
          case ProvisioningStatus.authenticated:
          case ProvisioningStatus.unknown:
            // Not progress. An unrecognised state is never read as success.
            break;
        }
      }
    } on TimeoutException {
      throw StateError(
        'The gateway did not finish setting up. It may still be trying; check the dashboard in a minute.',
      );
    } finally {
      UniversalBle.onValueChange = null;
      await statuses.close();
      if (!finished) {
        // A finished setup has already restarted the gateway, so disconnecting
        // here is for the failure paths.
        try {
          await UniversalBle.disconnect(request.gateway.id);
        } catch (error) {
          debugPrint('Provisioning disconnect failed: $error');
        }
      }
    }
  }

  Future<void> _write(
    String deviceId,
    String characteristic,
    List<int> bytes, {
    bool withoutResponse = false,
  }) {
    return UniversalBle.write(
      deviceId,
      ProvisioningProtocol.service,
      characteristic,
      Uint8List.fromList(bytes),
      withoutResponse: withoutResponse,
    );
  }
}
