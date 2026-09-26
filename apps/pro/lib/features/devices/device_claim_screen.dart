import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/shared/design_system/colors.dart';
import '../../widgets/shared/design_system/tokens.dart';
import '../../widgets/shared/design_system/typography.dart';
import '../../widgets/shared/design_system/components.dart';
import '../../services/api_client.dart';
import 'qr_scan_screen.dart';
import '../../utils/error_messages.dart';

/// Claims an ESP32 gateway onto the signed-in account using the device's
/// printed claim code. Pushed as its own route so it can be shown modally
/// over the shell (back button returns to the device list unclaimed).
class DeviceClaimScreen extends StatefulWidget {
  const DeviceClaimScreen({Key? key}) : super(key: key);

  @override
  State<DeviceClaimScreen> createState() => _DeviceClaimScreenState();
}

class _DeviceClaimScreenState extends State<DeviceClaimScreen> {
  final _formKey = GlobalKey<FormState>();
  final _deviceIdController = TextEditingController();
  final _claimCodeController = TextEditingController();
  final APIClient _apiClient = APIClient();
  bool _isSubmitting = false;
  bool _success = false;

  @override
  void dispose() {
    _deviceIdController.dispose();
    _claimCodeController.dispose();
    super.dispose();
  }

  Future<void> _scanQrCode() async {
    final result = await context.push<DeviceClaimQrResult>('/devices/claim/scan');
    if (result == null || !mounted) return;
    setState(() {
      _deviceIdController.text = result.deviceId;
      _claimCodeController.text = result.claimCode;
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      await _apiClient.claimDevice(
        _deviceIdController.text.trim(),
        claimCode: _claimCodeController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _success = true;
        _isSubmitting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
      });
      JKBMSRToast.show(
        context,
        friendlyErrorMessage(e),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.canvas,
      appBar: JKBMSRNavigationBar(title: 'Claim Gateway'),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(JKBMSRTokens.space24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: _success ? _buildSuccess(context) : _buildForm(context),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccess(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(JKBMSRTokens.space32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 48, color: context.colors.accent),
            const SizedBox(height: JKBMSRTokens.space16),
            Text('Gateway claimed', style: JKBMSRTypography.cardHeading),
            const SizedBox(height: JKBMSRTokens.space8),
            Text(
              'Your gateway is now linked to this account and will appear in your gateway list.',
              textAlign: TextAlign.center,
              style: JKBMSRTypography.bodySecondary,
            ),
            const SizedBox(height: JKBMSRTokens.space24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => context.pop(true),
                child: const Text('Back to Gateways'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(JKBMSRTokens.space32),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add a Gateway', style: JKBMSRTypography.cardHeading),
              const SizedBox(height: JKBMSRTokens.space8),
              Text(
                'Enter the gateway ID and claim code printed on your ESP32 gateway label.',
                style: JKBMSRTypography.bodySecondary,
              ),
              const SizedBox(height: JKBMSRTokens.space24),
              OutlinedButton.icon(
                onPressed: _isSubmitting ? null : _scanQrCode,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan QR Code'),
              ),
              const SizedBox(height: JKBMSRTokens.space16),
              TextFormField(
                controller: _deviceIdController,
                enabled: !_isSubmitting,
                decoration: const InputDecoration(
                  labelText: 'Gateway ID',
                  hintText: 'e.g. JK-BMS-0F21A3',
                ),
                textInputAction: TextInputAction.next,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Gateway ID is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: JKBMSRTokens.space16),
              TextFormField(
                controller: _claimCodeController,
                enabled: !_isSubmitting,
                decoration: const InputDecoration(
                  labelText: 'Claim Code',
                  hintText: 'Printed on the gateway label',
                ),
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Claim code is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: JKBMSRTokens.space24),
              _isSubmitting
                  ? Center(child: CircularProgressIndicator(color: context.colors.accent))
                  : ElevatedButton(
                      onPressed: _submit,
                      child: const Text('Claim Gateway'),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
