import 'package:flutter/material.dart';

import '../../../theme/lumi_tokens.dart';

/// Scan reticle — green corner brackets marking the area a barcode scanner is
/// actually looking at. Flashes brighter on each accepted scan (driven by
/// [flashTick]).
///
/// The reticle is purely visual: callers must draw it over the same rect they
/// pass to `MobileScanner.scanWindow`, otherwise the drawn box and the
/// detection window drift apart.
class ScanReticle extends StatelessWidget {
  const ScanReticle({super.key, required this.size, this.flashTick = 0});

  final Size size;

  /// Bumped by the host screen each time a scan is accepted.
  final int flashTick;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(flashTick),
      tween: Tween<double>(begin: flashTick == 0 ? 0.0 : 1.0, end: 0.0),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOut,
      builder: (context, flash, _) {
        return SizedBox.fromSize(
          size: size,
          child: CustomPaint(painter: ScanReticlePainter(flash: flash)),
        );
      },
    );
  }
}

@visibleForTesting
class ScanReticlePainter extends CustomPainter {
  ScanReticlePainter({required this.flash});

  /// 0 = resting, 1 = just scanned.
  final double flash;

  @override
  void paint(Canvas canvas, Size size) {
    const armLength = 28.0;
    final rect = Offset.zero & size;
    final color = Color.lerp(
      LumiTokens.green.withValues(alpha: 0.9),
      LumiTokens.paper,
      flash,
    )!;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3 + flash * 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    _corner(canvas, paint, rect.topLeft, 1, 1, armLength);
    _corner(canvas, paint, rect.topRight, -1, 1, armLength);
    _corner(canvas, paint, rect.bottomLeft, 1, -1, armLength);
    _corner(canvas, paint, rect.bottomRight, -1, -1, armLength);

    if (flash > 0) {
      final fill = Paint()
        ..color = LumiTokens.green.withValues(alpha: 0.12 * flash);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(14)),
        fill,
      );
    }
  }

  void _corner(
    Canvas canvas,
    Paint paint,
    Offset corner,
    int dx,
    int dy,
    double len,
  ) {
    final path = Path()
      ..moveTo(corner.dx + dx * len, corner.dy)
      ..lineTo(corner.dx, corner.dy)
      ..lineTo(corner.dx, corner.dy + dy * len);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(ScanReticlePainter oldDelegate) =>
      oldDelegate.flash != flash;
}
