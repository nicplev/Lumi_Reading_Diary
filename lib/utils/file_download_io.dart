import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<String?> downloadTextFile({
  required String fileName,
  required String content,
}) async {
  final downloadsDir = await getDownloadsDirectory();
  final targetDir = downloadsDir ?? await getTemporaryDirectory();
  final file = File('${targetDir.path}/$fileName');
  await file.writeAsString(content);
  return file.path;
}
