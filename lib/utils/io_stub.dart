// Stub file for web compatibility
// This file provides stub implementations of dart:io classes for web builds

class File {
  final String path;

  File(this.path);

  Future<void> writeAsString(String contents) async {
    throw UnsupportedError('File operations are not supported on web');
  }
}

class Platform {
  static bool get isIOS => false;
  static bool get isAndroid => false;
}
