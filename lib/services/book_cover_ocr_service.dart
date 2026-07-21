import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../core/services/functions_instance.dart';

/// Suggested catalog metadata read off a book's front cover.
///
/// Confidence is per field because the two fail independently in practice:
/// a title is large display text and reads reliably, while an author's name
/// is small, often stylised, and sits next to an illustrator credit.
@immutable
class CoverOcrSuggestion {
  final String title;
  final double titleConfidence;
  final String author;
  final double authorConfidence;

  /// Model that produced this suggestion, reported by the server so stored
  /// provenance can't drift from what actually ran. Empty when nothing was
  /// suggested.
  final String model;

  const CoverOcrSuggestion({
    required this.title,
    required this.titleConfidence,
    required this.author,
    required this.authorConfidence,
    this.model = '',
  });

  static const empty = CoverOcrSuggestion(
    title: '',
    titleConfidence: 0,
    author: '',
    authorConfidence: 0,
  );

  bool get isEmpty => title.isEmpty && author.isEmpty;

  static double _confidence(Object? value) {
    final parsed = value is num ? value.toDouble() : 0.0;
    if (parsed.isNaN) return 0;
    return parsed.clamp(0.0, 1.0);
  }

  static String _text(Object? value) =>
      value is String ? value.trim() : '';

  factory CoverOcrSuggestion.fromMap(Map<Object?, Object?> map) {
    return CoverOcrSuggestion(
      title: _text(map['title']),
      titleConfidence: _confidence(map['titleConfidence']),
      author: _text(map['author']),
      authorConfidence: _confidence(map['authorConfidence']),
      model: _text(map['model']),
    );
  }
}

/// Longest edge, in pixels, of the image sent for OCR. A cover only has to be
/// legible — sending the full upload-sized JPEG would cost payload and latency
/// on classroom wifi for no gain in recognition.
const int kOcrMaxEdge = 1024;
const int kOcrJpegQuality = 80;

typedef CoverOcrCallableInvoker = Future<Object?> Function(
    String name, Map<String, dynamic> args,
    {required bool limitedUseAppCheckToken});

Future<Object?> _defaultInvoker(
  String name,
  Map<String, dynamic> args, {
  required bool limitedUseAppCheckToken,
}) async {
  final callable = lumiFunctions.httpsCallable(
    name,
    options: HttpsCallableOptions(
      limitedUseAppCheckToken: limitedUseAppCheckToken,
    ),
  );
  final res = await callable.call<Object?>(args);
  return res.data;
}

/// Downscales to [kOcrMaxEdge] and re-encodes as JPEG. Runs in an isolate —
/// this is the same shape as `CommunityBookService._processImage`, kept
/// separate because that one targets the upload size, not the model's.
Uint8List? _downscaleForOcr(Uint8List bytes) {
  final image = img.decodeImage(bytes);
  if (image == null) return null;

  final longest = image.width > image.height ? image.width : image.height;
  final resized = longest > kOcrMaxEdge
      ? img.copyResize(
          image,
          width: image.width >= image.height ? kOcrMaxEdge : null,
          height: image.width >= image.height ? null : kOcrMaxEdge,
          maintainAspect: true,
        )
      : image;

  return Uint8List.fromList(img.encodeJpg(resized, quality: kOcrJpegQuality));
}

/// Thin client wrapper around the `extractBookCoverMetadata` callable.
///
/// Used only when a teacher is contributing a book no catalog knows, to
/// pre-fill the title/author fields they would otherwise type by hand.
///
/// Every failure — offline, provider outage, kill switch off, malformed
/// response — resolves to [CoverOcrSuggestion.empty] rather than throwing.
/// The feature is purely additive: it must never block contributing a book.
class BookCoverOcrService {
  final CoverOcrCallableInvoker _invoke;

  BookCoverOcrService({CoverOcrCallableInvoker? invoker})
      : _invoke = invoker ?? _defaultInvoker;

  Future<CoverOcrSuggestion> readCover({
    required Uint8List coverBytes,
    required String schoolId,
  }) async {
    if (schoolId.isEmpty || coverBytes.isEmpty) {
      return CoverOcrSuggestion.empty;
    }
    try {
      final downscaled = await compute(_downscaleForOcr, coverBytes);
      if (downscaled == null) return CoverOcrSuggestion.empty;

      final data = await _invoke(
        'extractBookCoverMetadata',
        {
          'schoolId': schoolId,
          'imageBase64': base64Encode(downscaled),
        },
        limitedUseAppCheckToken: true,
      );
      if (data is! Map) return CoverOcrSuggestion.empty;
      return CoverOcrSuggestion.fromMap(data.cast<Object?, Object?>());
    } catch (e) {
      debugPrint('BookCoverOcrService.readCover failed: $e');
      return CoverOcrSuggestion.empty;
    }
  }
}
