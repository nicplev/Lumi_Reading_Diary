import 'package:flutter/material.dart';

class PersistentCachedImage extends StatelessWidget {
  const PersistentCachedImage({
    super.key,
    required this.imageUrl,
    required this.fallback,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.alignment = Alignment.center,
  });

  final String imageUrl;
  final Widget fallback;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    if (!imageUrl.startsWith('http')) return fallback;

    return Image.network(
      imageUrl,
      fit: fit,
      width: width,
      height: height,
      alignment: alignment,
      frameBuilder: (_, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) return child;
        return fallback;
      },
      loadingBuilder: (_, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return fallback;
      },
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}
