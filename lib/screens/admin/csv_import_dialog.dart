import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/csv_import_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/lumi_text_styles.dart';
import '../../core/theme/lumi_borders.dart';
import 'package:path_provider/path_provider.dart';
// Conditional import - use dart:io on mobile, stub on web
import 'dart:io' if (dart.library.html) '../../utils/io_stub.dart';

class CSVImportDialog extends StatefulWidget {
  final String schoolId;

  const CSVImportDialog({
    super.key,
    required this.schoolId,
  });

  @override
  State<CSVImportDialog> createState() => _CSVImportDialogState();
}

class _CSVImportDialogState extends State<CSVImportDialog> {
  final CSVImportService _csvService = CSVImportService();

  String? _fileName;
  String? _fileContent;
  List<CSVRow>? _parsedRows;
  List<String> _validationErrors = [];
  bool _isLoading = false;
  bool _isParsing = false;
  bool _isImporting = false;
  CSVImportResult? _importResult;
  final TextEditingController _csvTextController = TextEditingController();
  bool _showTextInput = false;

  @override
  void dispose() {
    _csvTextController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: LumiBorders.large),
      child: Container(
        width: 800,
        constraints: const BoxConstraints(maxHeight: 700),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.rosePink.withValues(alpha: 0.1),
                    borderRadius: LumiBorders.large,
                  ),
                  child: const Icon(
                    Icons.upload_file,
                    color: AppColors.rosePink,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Import Students from CSV',
                        style: LumiTextStyles.h2(color: AppColors.charcoal)
                            .copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Upload a CSV file to bulk import students',
                        style: LumiTextStyles.body(
                            color: AppColors.charcoal.withValues(alpha: 0.6)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close,
                      color: AppColors.charcoal.withValues(alpha: 0.6)),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 24),

            // Content
            Expanded(
              child: _buildContent(),
            ),

            // Actions
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_importResult != null) {
      return _buildResultView();
    }

    if (_parsedRows != null && _validationErrors.isEmpty) {
      return _buildPreviewView();
    }

    if (_validationErrors.isNotEmpty) {
      return _buildErrorView();
    }

    return _buildUploadView();
  }

  Widget _buildUploadView() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Instructions
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.1),
              borderRadius: LumiBorders.large,
              border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.info_outline,
                        color: AppColors.info, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'CSV Format Requirements',
                      style: LumiTextStyles.body(color: AppColors.info)
                          .copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildRequirement(
                    'Student ID, First Name, Last Name, and Class Name are required'),
                _buildRequirement('Date of Birth must be in YYYY-MM-DD format'),
                _buildRequirement('Parent Email must be a valid email address'),
                _buildRequirement(
                    'Classes will be created automatically if they don\'t exist'),
                _buildRequirement('Duplicate Student IDs will be skipped'),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Download/Share Template
          Center(
            child: OutlinedButton.icon(
              onPressed: _downloadTemplate,
              icon: Icon(
                _isMobilePlatform() ? Icons.share : Icons.download,
                color: AppColors.rosePink,
              ),
              label: Text(
                _isMobilePlatform()
                    ? 'Share CSV Template'
                    : 'Download CSV Template',
                style: const TextStyle(
                    color: AppColors.rosePink, fontWeight: FontWeight.bold),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.rosePink),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: LumiBorders.large),
              ),
            ),
          ),

          const SizedBox(height: 32),

          // Mobile: Show paste option, Desktop: Show file picker
          if (_isMobilePlatform()) ...[
            // Text Input for Mobile
            if (_showTextInput) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: LumiBorders.large,
                  border: Border.all(
                      color: AppColors.charcoal.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Paste CSV Content',
                      style: LumiTextStyles.body(color: AppColors.charcoal)
                          .copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _csvTextController,
                      maxLines: 10,
                      decoration: InputDecoration(
                        hintText:
                            'Student ID,First Name,Last Name,Class Name...\nS001,John,Doe,3A...',
                        border: OutlineInputBorder(
                          borderRadius: LumiBorders.medium,
                        ),
                        filled: true,
                        fillColor: AppColors.offWhite,
                      ),
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setState(() {
                                _showTextInput = false;
                                _csvTextController.clear();
                              });
                            },
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isParsing ? null : _parseTextInput,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.rosePink,
                              foregroundColor: Colors.white,
                            ),
                            child: _isParsing
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2),
                                  )
                                : const Text('Parse CSV'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Button to show text input
              InkWell(
                onTap: () {
                  setState(() {
                    _showTextInput = true;
                  });
                },
                borderRadius: LumiBorders.large,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(48),
                  decoration: BoxDecoration(
                    color: AppColors.rosePink.withValues(alpha: 0.05),
                    borderRadius: LumiBorders.large,
                    border: Border.all(
                      color: AppColors.rosePink.withValues(alpha: 0.3),
                      width: 2,
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.content_paste,
                        size: 64,
                        color: AppColors.rosePink.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Tap to paste CSV content',
                        style: LumiTextStyles.h3(color: AppColors.rosePink)
                            .copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Copy your CSV data and paste it here',
                        style: LumiTextStyles.body(
                            color: AppColors.charcoal.withValues(alpha: 0.6)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ] else ...[
            // File Picker for Desktop
            InkWell(
              onTap: _isLoading ? null : _pickFile,
              borderRadius: LumiBorders.large,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(48),
                decoration: BoxDecoration(
                  color: AppColors.rosePink.withValues(alpha: 0.05),
                  borderRadius: LumiBorders.large,
                  border: Border.all(
                    color: AppColors.rosePink.withValues(alpha: 0.3),
                    width: 2,
                    style: BorderStyle.solid,
                  ),
                ),
                child: Column(
                  children: [
                    if (_isLoading)
                      const CircularProgressIndicator(color: AppColors.rosePink)
                    else
                      Icon(
                        Icons.cloud_upload_outlined,
                        size: 64,
                        color: AppColors.rosePink.withValues(alpha: 0.5),
                      ),
                    const SizedBox(height: 16),
                    Text(
                      _fileName ?? 'Click to select CSV file',
                      style: LumiTextStyles.h3(color: AppColors.rosePink)
                          .copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'or drag and drop',
                      style: LumiTextStyles.body(
                          color: AppColors.charcoal.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRequirement(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Icon(Icons.check_circle, color: AppColors.info, size: 16),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: AppColors.charcoal, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Summary
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.1),
            borderRadius: LumiBorders.large,
            border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle,
                  color: AppColors.success, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ready to Import',
                      style: LumiTextStyles.body(color: AppColors.success)
                          .copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_parsedRows!.length} students will be imported',
                      style: const TextStyle(
                          color: AppColors.charcoal, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Preview Table
        Text(
          'Preview',
          style: LumiTextStyles.h3(color: AppColors.charcoal)
              .copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),

        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border:
                  Border.all(color: AppColors.charcoal.withValues(alpha: 0.2)),
              borderRadius: LumiBorders.medium,
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(AppColors.charcoal
                      .withValues(alpha: 0.2)
                      .withValues(alpha: 0.3)),
                  columns: const [
                    DataColumn(
                        label: Text('Row',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Student ID',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('First Name',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Last Name',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Class',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('DOB',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Reading Level',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                  rows: _parsedRows!.take(50).map((row) {
                    return DataRow(cells: [
                      DataCell(Text(row.rowNumber.toString())),
                      DataCell(Text(row.studentId)),
                      DataCell(Text(row.firstName)),
                      DataCell(Text(row.lastName)),
                      DataCell(Text(row.className)),
                      DataCell(Text(row.dateOfBirth ?? '-')),
                      DataCell(Text(row.readingLevel ?? '-')),
                    ]);
                  }).toList(),
                ),
              ),
            ),
          ),
        ),

        if (_parsedRows!.length > 50)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Showing first 50 of ${_parsedRows!.length} students',
              style: TextStyle(
                  color: AppColors.charcoal.withValues(alpha: 0.6),
                  fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _buildErrorView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Error Summary
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.1),
            borderRadius: LumiBorders.large,
            border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.error, color: AppColors.error, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Validation Errors',
                      style: LumiTextStyles.body(color: AppColors.error)
                          .copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_validationErrors.length} errors found in the CSV file',
                      style: const TextStyle(
                          color: AppColors.charcoal, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Error List
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: LumiBorders.medium,
              border:
                  Border.all(color: AppColors.charcoal.withValues(alpha: 0.2)),
            ),
            child: ListView.separated(
              itemCount: _validationErrors.length,
              separatorBuilder: (context, index) => const Divider(height: 16),
              itemBuilder: (context, index) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning,
                        color: AppColors.warning, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _validationErrors[index],
                        style: const TextStyle(
                            color: AppColors.charcoal, fontSize: 14),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResultView() {
    final result = _importResult!;
    final hasErrors = result.errorCount > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Result Summary
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: hasErrors
                ? AppColors.warning.withValues(alpha: 0.1)
                : AppColors.success.withValues(alpha: 0.1),
            borderRadius: LumiBorders.large,
            border: Border.all(
              color: hasErrors
                  ? AppColors.warning.withValues(alpha: 0.3)
                  : AppColors.success.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Icon(
                hasErrors ? Icons.warning : Icons.check_circle,
                color: hasErrors ? AppColors.warning : AppColors.success,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasErrors
                          ? 'Import Completed with Errors'
                          : 'Import Successful',
                      style: LumiTextStyles.body(
                              color: hasErrors
                                  ? AppColors.warning
                                  : AppColors.success)
                          .copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${result.successCount} students imported successfully',
                      style: const TextStyle(
                          color: AppColors.charcoal, fontSize: 14),
                    ),
                    if (hasErrors)
                      Text(
                        '${result.errorCount} students failed to import',
                        style: const TextStyle(
                            color: AppColors.error, fontSize: 14),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Error Details (if any)
        if (hasErrors) ...[
          Text(
            'Import Errors',
            style: LumiTextStyles.h3(color: AppColors.charcoal)
                .copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: LumiBorders.medium,
                border: Border.all(
                    color: AppColors.charcoal.withValues(alpha: 0.2)),
              ),
              child: ListView.separated(
                itemCount: result.errors.length,
                separatorBuilder: (context, index) => const Divider(height: 16),
                itemBuilder: (context, index) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline,
                          color: AppColors.error, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          result.errors[index],
                          style: const TextStyle(
                              color: AppColors.charcoal, fontSize: 14),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ] else ...[
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 64,
                    color: AppColors.success.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'All students imported successfully!',
                    style: LumiTextStyles.h3(color: AppColors.success)
                        .copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildActions() {
    if (_importResult != null) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ElevatedButton(
            onPressed: () =>
                Navigator.of(context).pop(true), // Return true to refresh
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.rosePink,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: LumiBorders.large),
            ),
            child: const Text('Done',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      );
    }

    if (_parsedRows != null && _validationErrors.isEmpty) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton(
            onPressed: _reset,
            child: Text('Cancel',
                style: TextStyle(
                    color: AppColors.charcoal.withValues(alpha: 0.6))),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: OutlinedButton(
                    onPressed: _reset,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                          color: AppColors.charcoal.withValues(alpha: 0.6)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: LumiBorders.large),
                    ),
                    child: Text(
                      'Reset',
                      style: TextStyle(
                          color: AppColors.charcoal.withValues(alpha: 0.6)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: ElevatedButton(
                    onPressed: _isImporting ? null : _importStudents,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.rosePink,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: LumiBorders.large),
                    ),
                    child: _isImporting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : const Text(
                            'Import',
                            style: TextStyle(fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (_validationErrors.isNotEmpty) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel',
                style: TextStyle(
                    color: AppColors.charcoal.withValues(alpha: 0.6))),
          ),
          ElevatedButton(
            onPressed: _reset,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.rosePink,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: LumiBorders.large),
            ),
            child: const Text('Choose Different File',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel',
              style:
                  TextStyle(color: AppColors.charcoal.withValues(alpha: 0.6))),
        ),
      ],
    );
  }

  Future<void> _pickFile() async {
    try {
      setState(() => _isLoading = true);

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );

      if (result != null && result.files.single.bytes != null) {
        final bytes = result.files.single.bytes!;
        final content = String.fromCharCodes(bytes);

        setState(() {
          _fileName = result.files.single.name;
          _fileContent = content;
        });

        await _parseAndValidate();
      }
    } catch (e) {
      _showError('Error picking file: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _parseTextInput() async {
    if (_csvTextController.text.trim().isEmpty) {
      _showError('Please paste CSV content first');
      return;
    }

    setState(() {
      _fileName = 'Pasted CSV';
      _fileContent = _csvTextController.text;
      _showTextInput = false;
    });

    await _parseAndValidate();
  }

  Future<void> _parseAndValidate() async {
    if (_fileContent == null) return;

    try {
      setState(() => _isParsing = true);

      final rows = await _csvService.parseCSV(_fileContent!);
      final errors = _csvService.validateRows(rows);

      setState(() {
        _parsedRows = rows;
        _validationErrors = errors;
        _isParsing = false;
      });
    } catch (e) {
      setState(() {
        _validationErrors = ['Failed to parse CSV: $e'];
        _isParsing = false;
      });
    }
  }

  Future<void> _importStudents() async {
    if (_parsedRows == null) return;

    try {
      setState(() => _isImporting = true);

      final result = await _csvService.importStudents(
        rows: _parsedRows!,
        schoolId: widget.schoolId,
      );

      setState(() {
        _importResult = result;
        _isImporting = false;
      });
    } catch (e) {
      _showError('Import failed: $e');
      setState(() => _isImporting = false);
    }
  }

  bool _isMobilePlatform() {
    // Check if running on mobile (iOS or Android)
    if (kIsWeb) return false;
    return Platform.isIOS || Platform.isAndroid;
  }

  Future<void> _downloadTemplate() async {
    if (_isMobilePlatform()) {
      await _shareTemplateOnMobile();
    } else {
      await _downloadTemplateDesktop();
    }
  }

  Future<void> _shareTemplateOnMobile() async {
    try {
      final template = _csvService.generateTemplate();

      // Use temporary directory (works on iOS and Android without permissions)
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/student_import_template.csv');
      await file.writeAsString(template);

      // Share using native share sheet with XFile
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Student Import Template',
          text:
              'CSV template for bulk importing students into Lumi Reading Tracker',
        ),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Template ready to share'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      _showError('Error sharing template: $e');
    }
  }

  Future<void> _downloadTemplateDesktop() async {
    try {
      final template = _csvService.generateTemplate();

      // Get downloads directory (works on desktop platforms)
      final directory = await getDownloadsDirectory();
      if (directory == null) {
        _showError('Could not access downloads directory');
        return;
      }

      // Save template file
      final file = File('${directory.path}/student_import_template.csv');
      await file.writeAsString(template);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Template saved to ${file.path}'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      _showError('Error saving template: $e');
    }
  }

  void _reset() {
    setState(() {
      _fileName = null;
      _fileContent = null;
      _parsedRows = null;
      _validationErrors = [];
      _importResult = null;
      _showTextInput = false;
      _csvTextController.clear();
    });
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }
}
