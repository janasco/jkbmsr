import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../widgets/shared/design_system/colors.dart';
import '../../widgets/shared/design_system/tokens.dart';
import '../../widgets/shared/design_system/typography.dart';
import '../../widgets/shared/design_system/components.dart';

/// Result of a successful device-claim QR scan: the device ID and claim
/// code parsed out of the onboard URL (matches the format jkbmsr-web
/// renders on /onboard: https://app.jkbmsr.com/onboard?device=..&code=..).
class DeviceClaimQrResult {
  final String deviceId;
  final String claimCode;

  const DeviceClaimQrResult({required this.deviceId, required this.claimCode});
}

/// Parses a scanned barcode value into a [DeviceClaimQrResult], or null if
/// it isn't a recognizable device-claim URL (wrong QR, malformed link,
/// missing device/code params). Exposed as a standalone function so it can
/// be unit-tested without driving an actual camera stream.
DeviceClaimQrResult? parseDeviceClaimQr(String? rawValue) {
  if (rawValue == null || rawValue.isEmpty) return null;
  final uri = Uri.tryParse(rawValue);
  if (uri == null) return null;
  final deviceId = uri.queryParameters['device'];
  final claimCode = uri.queryParameters['code'];
  if (deviceId == null || deviceId.isEmpty || claimCode == null || claimCode.isEmpty) {
    return null;
  }
  return DeviceClaimQrResult(deviceId: deviceId, claimCode: claimCode);
}

/// Full-screen camera scanner for the device-claim QR code. Pops with a
/// [DeviceClaimQrResult] on a valid scan, or null if the user backs out.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({Key? key}) : super(key: key);

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final result = parseDeviceClaimQr(barcode.rawValue);
      if (result != null) {
        _handled = true;
        Navigator.of(context).pop(result);
        return;
      }
    }
    JKBMSRToast.show(
      context,
      'Could not read a valid gateway QR code. Try again or enter it manually.',
      isError: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: JKBMSRNavigationBar(title: 'Scan Gateway QR Code'),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(JKBMSRTokens.space24),
              color: context.colors.canvas.withValues(alpha: 0.85),
              child: Text(
                'Point the camera at the QR code shown on the gateway setup page.',
                textAlign: TextAlign.center,
                style: JKBMSRTypography.bodySecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
