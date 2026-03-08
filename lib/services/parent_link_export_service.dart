import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/file_download.dart';
import 'dart:io' if (dart.library.html) '../utils/io_stub.dart';

class LinkCodeExportRow {
  final String studentName;
  final String studentId;
  final String className;
  final String code;
  final String status;
  final String createdAt;
  final String expiresAt;
  final int linkedParentCount;

  const LinkCodeExportRow({
    required this.studentName,
    required this.studentId,
    required this.className,
    required this.code,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    required this.linkedParentCount,
  });
}

class ParentLinkExportResult {
  final bool success;
  final String message;
  final String? path;

  const ParentLinkExportResult({
    required this.success,
    required this.message,
    this.path,
  });
}

class ParentLinkExportService {
  String buildCsv(List<LinkCodeExportRow> rows) {
    final csvRows = <List<dynamic>>[
      [
        'Student Name',
        'Student ID',
        'Class',
        'Link Code',
        'Code Status',
        'Created At',
        'Expires At',
        'Linked Parent Count',
      ],
      ...rows.map(
        (row) => [
          row.studentName,
          row.studentId,
          row.className,
          row.code,
          row.status,
          row.createdAt,
          row.expiresAt,
          row.linkedParentCount,
        ],
      ),
    ];

    return const ListToCsvConverter().convert(csvRows);
  }

  bool _isMobilePlatform() {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  Future<ParentLinkExportResult> exportCsv({
    required String csvContent,
    String fileName = 'parent_link_codes.csv',
  }) async {
    try {
      if (_isMobilePlatform()) {
        final tempDir = await getTemporaryDirectory();
        final path = '${tempDir.path}/$fileName';
        final file = File(path);
        await file.writeAsString(csvContent);
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(path)],
            subject: 'Lumi Parent Link Codes',
            text:
                'Parent linking codes export from Lumi. Share this securely with school staff.',
          ),
        );
        return const ParentLinkExportResult(
          success: true,
          message: 'CSV prepared and shared.',
        );
      }

      final path = await downloadTextFile(
        fileName: fileName,
        content: csvContent,
      );
      return ParentLinkExportResult(
        success: true,
        message: path == null
            ? 'CSV downloaded.'
            : 'CSV saved to $path',
        path: path,
      );
    } catch (e) {
      return ParentLinkExportResult(
        success: false,
        message: 'Failed to export CSV: $e',
      );
    }
  }
}
