import 'dart:io';

import 'package:flutter/material.dart';

import '../../../services/persistent_image_cache_service.dart';

class PersistentCachedImage extends StatefulWidget {
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
  State<PersistentCachedImage> createState() => _PersistentCachedImageState();
}

class _PersistentCachedImageState extends State<PersistentCachedImage> {
  String? _cachedPath;
  String? _resolvingUrl;
  bool _cacheLookupComplete = false;

  @override
  void initState() {
    super.initState();
    _resolveCachedPath();
  }

  @override
  void didUpdateWidget(covariant PersistentCachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _cachedPath = null;
      _cacheLookupComplete = false;
      _resolveCachedPath();
    }
  }

  Future<void> _resolveCachedPath() async {
    final imageUrl = widget.imageUrl.trim();
    if (imageUrl.isEmpty || !imageUrl.startsWith('http')) {
      if (!mounted) return;
      setState(() {
        _cacheLookupComplete = true;
      });
      return;
    }

    _resolvingUrl = imageUrl;
    final cachedPath =
        await PersistentImageCacheService.instance.getCachedFilePath(imageUrl);

    if (!mounted || _resolvingUrl != imageUrl) return;
    if (_cachedPath == cachedPath && _cacheLookupComplete) return;

    setState(() {
      _cachedPath = cachedPath;
      _cacheLookupComplete = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = widget.imageUrl.trim();
    if (imageUrl.isEmpty || !imageUrl.startsWith('http')) {
      return widget.fallback;
    }

    if (_cachedPath != null) {
      return Image.file(
        File(_cachedPath!),
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        alignment: widget.alignment,
        frameBuilder: (_, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) return child;
          return widget.fallback;
        },
        errorBuilder: (_, __, ___) => _buildNetworkImage(imageUrl),
      );
    }

    if (!_cacheLookupComplete) {
      return widget.fallback;
    }

    return _buildNetworkImage(imageUrl);
  }

  Widget _buildNetworkImage(String imageUrl) {
    return Image.network(
      imageUrl,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      alignment: widget.alignment,
      frameBuilder: (_, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) return child;
        return widget.fallback;
      },
      loadingBuilder: (_, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return widget.fallback;
      },
      errorBuilder: (_, __, ___) => widget.fallback,
    );
  }
}
