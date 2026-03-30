import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class PersistentImageCacheService {
  PersistentImageCacheService._({
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  static final PersistentImageCacheService instance =
      PersistentImageCacheService._();

  final http.Client _httpClient;
  final Map<String, Future<String?>> _inFlight = {};
  final Map<String, String> _resolvedPaths = {};

  Directory? _cacheDirectory;
  bool _cleanupScheduled = false;

  static const _requestTimeout = Duration(seconds: 8);
  static const _refreshAfter = Duration(days: 30);
  static const _purgeAfter = Duration(days: 120);
  static const _maxFiles = 500;

  Future<String?> getCachedFilePath(String imageUrl) {
    final url = imageUrl.trim();
    if (url.isEmpty || !url.startsWith('http')) {
      return Future<String?>.value(null);
    }

    final inFlight = _inFlight[url];
    if (inFlight != null) return inFlight;

    final future = _resolveCachedPath(url);
    _inFlight[url] = future;
    future.whenComplete(() => _inFlight.remove(url));
    return future;
  }

  Future<String?> _resolveCachedPath(String imageUrl) async {
    final knownPath = _resolvedPaths[imageUrl];
    if (knownPath != null && await File(knownPath).exists()) {
      _refreshStaleCacheInBackground(imageUrl, File(knownPath));
      return knownPath;
    }

    final file = await _fileForUrl(imageUrl);
    if (await file.exists()) {
      _resolvedPaths[imageUrl] = file.path;
      _refreshStaleCacheInBackground(imageUrl, file);
      return file.path;
    }

    final wroteFile = await _downloadToFile(imageUrl, file);
    if (!wroteFile || !await file.exists()) return null;

    _resolvedPaths[imageUrl] = file.path;
    return file.path;
  }

  void _refreshStaleCacheInBackground(String imageUrl, File file) {
    unawaited(() async {
      try {
        final stat = await file.stat();
        if (DateTime.now().difference(stat.modified) < _refreshAfter) {
          return;
        }
        await _downloadToFile(imageUrl, file);
      } catch (_) {
        // Keep using existing cached file.
      }
    }());
  }

  Future<File> _fileForUrl(String imageUrl) async {
    final cacheDir = await _ensureCacheDirectory();
    final hash = sha256.convert(utf8.encode(imageUrl)).toString();
    final ext = _extensionForUrl(imageUrl);
    return File('${cacheDir.path}/$hash$ext');
  }

  Future<Directory> _ensureCacheDirectory() async {
    if (_cacheDirectory != null) return _cacheDirectory!;

    final baseDir = await getApplicationSupportDirectory();
    final cacheDir = Directory('${baseDir.path}/book_cover_cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }

    _cacheDirectory = cacheDir;
    _scheduleCleanup(cacheDir);
    return cacheDir;
  }

  void _scheduleCleanup(Directory cacheDir) {
    if (_cleanupScheduled) return;
    _cleanupScheduled = true;

    unawaited(() async {
      try {
        final now = DateTime.now();
        final files = <_CachedFile>[];

        await for (final entity in cacheDir.list(followLinks: false)) {
          if (entity is! File) continue;
          final stat = await entity.stat();
          if (now.difference(stat.modified) > _purgeAfter) {
            await entity.delete();
            continue;
          }
          files.add(_CachedFile(file: entity, modified: stat.modified));
        }

        if (files.length > _maxFiles) {
          files.sort((a, b) => a.modified.compareTo(b.modified));
          final overflow = files.length - _maxFiles;
          for (var i = 0; i < overflow; i++) {
            await files[i].file.delete();
          }
        }
      } catch (_) {
        // Cleanup is best effort and should never break image rendering.
      }
    }());
  }

  Future<bool> _downloadToFile(String imageUrl, File file) async {
    File? tempFile;
    try {
      final response =
          await _httpClient.get(Uri.parse(imageUrl)).timeout(_requestTimeout);
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        return false;
      }

      final contentType = response.headers['content-type'];
      if (contentType != null &&
          contentType.isNotEmpty &&
          !contentType.startsWith('image/')) {
        return false;
      }

      tempFile = File('${file.path}.tmp');
      await tempFile.writeAsBytes(response.bodyBytes, flush: true);
      if (await file.exists()) {
        await file.delete();
      }
      await tempFile.rename(file.path);
      return true;
    } catch (_) {
      return false;
    } finally {
      if (tempFile != null && await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  String _extensionForUrl(String imageUrl) {
    final uri = Uri.tryParse(imageUrl);
    final lastPath =
        uri?.pathSegments.isNotEmpty == true ? uri!.pathSegments.last : '';
    final match = RegExp(r'\.(png|jpg|jpeg|webp|gif)$', caseSensitive: false)
        .firstMatch(lastPath);
    final extension = match?.group(1)?.toLowerCase();
    return extension == null ? '.img' : '.$extension';
  }
}

class _CachedFile {
  const _CachedFile({
    required this.file,
    required this.modified,
  });

  final File file;
  final DateTime modified;
}
