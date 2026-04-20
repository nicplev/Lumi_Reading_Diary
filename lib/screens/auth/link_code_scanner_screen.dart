import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/lumi_text_styles.dart';

/// Full-screen QR scanner that returns an 8-character alphanumeric link code
/// to the caller via [Navigator.pop]. Returns `null` if the user cancels.
class LinkCodeScannerScreen extends StatefulWidget {
  const LinkCodeScannerScreen({super.key});

  @override
  State<LinkCodeScannerScreen> createState() => _LinkCodeScannerScreenState();
}

class _LinkCodeScannerScreenState extends State<LinkCodeScannerScreen> {
  static final RegExp _codePattern = RegExp(r'^[A-Z0-9]{8}$');

  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  bool _handled = false;
  bool _torchOn = false;
  PermissionStatus? _permissionStatus;

  @override
  void initState() {
    super.initState();
    _requestPermission();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _requestPermission() async {
    final current = await Permission.camera.status;
    final granted = current == PermissionStatus.granted ||
        current == PermissionStatus.limited;
    final resolved = granted ? current : await Permission.camera.request();
    if (!mounted) return;
    setState(() => _permissionStatus = resolved);
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue?.trim().toUpperCase();
      if (raw == null) continue;
      if (!_codePattern.hasMatch(raw)) continue;
      _handled = true;
      HapticFeedback.selectionClick();
      _controller.stop();
      Navigator.of(context).pop(raw);
      return;
    }
  }

  Future<void> _toggleTorch() async {
    await _controller.toggleTorch();
    if (!mounted) return;
    setState(() => _torchOn = !_torchOn);
  }

  bool get _isGranted =>
      _permissionStatus == PermissionStatus.granted ||
      _permissionStatus == PermissionStatus.limited;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_permissionStatus == null)
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            else if (!_isGranted)
              _buildPermissionDenied()
            else
              _buildScanner(),
            _buildTopBar(),
            if (_isGranted) _buildInstructions(),
          ],
        ),
      ),
    );
  }

  Widget _buildScanner() {
    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          errorBuilder: (context, error) => _buildCameraError(),
        ),
        const Center(child: _ScannerReticle()),
      ],
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.of(context).pop(),
              tooltip: 'Close',
            ),
            if (_isGranted)
              IconButton(
                icon: Icon(
                  _torchOn ? Icons.flash_on : Icons.flash_off,
                  color: Colors.white,
                  size: 28,
                ),
                onPressed: _toggleTorch,
                tooltip: _torchOn ? 'Turn off torch' : 'Turn on torch',
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructions() {
    return Positioned(
      left: 24,
      right: 24,
      bottom: 40,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'Point your camera at the QR code in the welcome email from your school.',
          textAlign: TextAlign.center,
          style: LumiTextStyles.body(color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildPermissionDenied() {
    final permanentlyDenied =
        _permissionStatus == PermissionStatus.permanentlyDenied ||
            _permissionStatus == PermissionStatus.restricted;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography,
                color: Colors.white, size: 64),
            const SizedBox(height: 16),
            Text(
              'Camera access needed',
              style: LumiTextStyles.h3(color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              permanentlyDenied
                  ? 'Enable camera access in Settings so Lumi can scan the QR code from your email.'
                  : 'Allow camera access to scan the QR code from your welcome email.',
              textAlign: TextAlign.center,
              style: LumiTextStyles.body(color: Colors.white70),
            ),
            const SizedBox(height: 24),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.rosePink,
              ),
              onPressed: permanentlyDenied
                  ? () async {
                      await openAppSettings();
                    }
                  : _requestPermission,
              child: Text(permanentlyDenied ? 'Open Settings' : 'Allow camera'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'Camera is unavailable on this device. You can still type the code manually.',
          textAlign: TextAlign.center,
          style: LumiTextStyles.body(color: Colors.white70),
        ),
      ),
    );
  }
}

class _ScannerReticle extends StatelessWidget {
  const _ScannerReticle();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: 240,
        height: 240,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 3),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 32,
              spreadRadius: 2,
            ),
          ],
        ),
      ),
    );
  }
}
