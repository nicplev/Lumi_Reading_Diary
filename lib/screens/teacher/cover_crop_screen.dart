import 'dart:io';
import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/teacher_constants.dart';

/// Full-screen crop step shown after the user picks or captures a book cover
/// image. Returns the cropped [File] on acceptance, or null on cancellation.
class CoverCropScreen extends StatefulWidget {
  const CoverCropScreen({super.key, required this.imageBytes});

  final Uint8List imageBytes;

  @override
  State<CoverCropScreen> createState() => _CoverCropScreenState();
}

class _CoverCropScreenState extends State<CoverCropScreen> {
  late Uint8List _bytes;
  final _cropController = CropController();
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _bytes = widget.imageBytes;
  }

  Future<void> _rotate() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    final rotated = await compute(_rotateImage90, _bytes);
    if (!mounted) return;
    setState(() {
      _bytes = rotated;
      _isProcessing = false;
    });
  }

  void _accept() {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    _cropController.crop();
  }

  Future<void> _onCropped(Uint8List croppedBytes) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final file = File(
        '${tempDir.path}/cover_crop_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await file.writeAsBytes(croppedBytes, flush: true);
      if (!mounted) return;
      Navigator.of(context).pop(file);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to process image. Please try again.')),
      );
    }
  }

  static Uint8List _rotateImage90(Uint8List bytes) {
    final image = img.decodeImage(bytes);
    if (image == null) return bytes;
    final rotated = img.copyRotate(image, angle: 90);
    return Uint8List.fromList(img.encodeJpg(rotated, quality: 92));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.teacherBackground,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        leading: TextButton(
          onPressed: _isProcessing ? null : () => Navigator.of(context).pop(null),
          child: Text(
            'Cancel',
            style: TeacherTypography.bodyMedium.copyWith(
              color: _isProcessing ? AppColors.textSecondary : AppColors.charcoal,
            ),
          ),
        ),
        leadingWidth: 80,
        title: Text('Adjust Cover', style: TeacherTypography.h3),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Crop(
                    image: _bytes,
                    controller: _cropController,
                    withCircleUi: false,
                    initialSize: 0.9,
                    baseColor: AppColors.teacherBackground,
                    maskColor: Colors.black54,
                    onCropped: _onCropped,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _isProcessing ? null : _rotate,
                      icon: const Icon(Icons.rotate_right_rounded),
                      tooltip: 'Rotate 90°',
                      style: IconButton.styleFrom(
                        foregroundColor: AppColors.charcoal,
                      ),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _isProcessing ? null : _accept,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.teacherPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(TeacherDimensions.radiusM),
                        ),
                      ),
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Use This Cover'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_isProcessing)
            const ColoredBox(
              color: Colors.black26,
              child: Center(
                child: CircularProgressIndicator(color: AppColors.teacherPrimary),
              ),
            ),
        ],
      ),
    );
  }
}
