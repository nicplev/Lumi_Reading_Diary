import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../data/models/class_model.dart';
import '../../data/models/student_model.dart';
import '../../data/models/reading_log_model.dart';
import '../../services/pdf_report_service.dart';
import '../../services/firebase_service.dart';
import '../../core/theme/app_colors.dart';

/// Screen for generating class-level summary reports
/// Used by teachers and admins to get overview of class performance
class ClassReportScreen extends StatefulWidget {
  final ClassModel classModel;

  const ClassReportScreen({
    super.key,
    required this.classModel,
  });

  @override
  State<ClassReportScreen> createState() => _ClassReportScreenState();
}

class _ClassReportScreenState extends State<ClassReportScreen> {
  final _pdfService = PdfReportService();
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  bool _isGenerating = false;
  File? _generatedReport;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Class Report'),
        backgroundColor: AppColors.primary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildClassCard(),
            const SizedBox(height: 24),
            _buildDateRangeSelector(),
            const SizedBox(height: 24),
            _buildReportPreview(),
            const SizedBox(height: 24),
            _buildActionButtons(),
            if (_generatedReport != null) ...[
              const SizedBox(height: 24),
              _buildGeneratedReportCard(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildClassCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Class Information',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.class_,
                    size: 32,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.classModel.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Year ${widget.classModel.yearLevel ?? "N/A"} | Room ${widget.classModel.room ?? "N/A"}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.grey[600],
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.classModel.studentIds.length} students',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateRangeSelector() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Report Period',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildDateButton(
                    label: 'Start Date',
                    date: _startDate,
                    onTap: () => _selectDate(context, isStartDate: true),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildDateButton(
                    label: 'End Date',
                    date: _endDate,
                    onTap: () => _selectDate(context, isStartDate: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildQuickRangeChip('Last Week', 7),
                _buildQuickRangeChip('Last Month', 30),
                _buildQuickRangeChip('Last Term', 90),
                _buildQuickRangeChip('This Year', null),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateButton({
    required String label,
    required DateTime date,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.primary),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              DateFormat('MMM dd, yyyy').format(date),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickRangeChip(String label, int? days) {
    return ActionChip(
      label: Text(label),
      onPressed: () {
        setState(() {
          if (days != null) {
            _startDate = DateTime.now().subtract(Duration(days: days));
            _endDate = DateTime.now();
          } else {
            // This year
            _startDate = DateTime(DateTime.now().year, 1, 1);
            _endDate = DateTime.now();
          }
        });
      },
    );
  }

  Widget _buildReportPreview() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.preview, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'Report Preview',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildPreviewItem(
              icon: Icons.calendar_today,
              label: 'Period',
              value:
                  '${DateFormat('MMM dd').format(_startDate)} - ${DateFormat('MMM dd, yyyy').format(_endDate)}',
            ),
            const Divider(),
            _buildPreviewItem(
              icon: Icons.people,
              label: 'Students',
              value: '${widget.classModel.studentIds.length} students',
            ),
            const Divider(),
            _buildPreviewItem(
              icon: Icons.description,
              label: 'Includes',
              value:
                  'Class overview, engagement metrics, top performers, students needing support, trends',
            ),
            const Divider(),
            _buildPreviewItem(
              icon: Icons.format_size,
              label: 'Format',
              value: 'PDF (A4)',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[600],
                      ),
                ),
                Text(
                  value,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          onPressed: _isGenerating ? null : _generateReport,
          icon: _isGenerating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Icon(Icons.picture_as_pdf),
          label: Text(_isGenerating ? 'Generating...' : 'Generate Class Report'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.all(16),
          ),
        ),
        if (_generatedReport != null) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _shareReport,
            icon: const Icon(Icons.share),
            label: const Text('Share Report'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.all(16),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _printReport,
            icon: const Icon(Icons.print),
            label: const Text('Print Report'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.all(16),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildGeneratedReportCard() {
    return Card(
      elevation: 2,
      color: Colors.green[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green[700], size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Report Generated Successfully!',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.green[900],
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Saved to: ${_generatedReport!.path.split('/').last}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.green[700],
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectDate(BuildContext context,
      {required bool isStartDate}) async {
    final initialDate = isStartDate ? _startDate : _endDate;
    final firstDate = DateTime(2020);
    final lastDate = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );

    if (picked != null) {
      setState(() {
        if (isStartDate) {
          _startDate = picked;
          // Ensure start date is before end date
          if (_startDate.isAfter(_endDate)) {
            _endDate = _startDate;
          }
        } else {
          _endDate = picked;
          // Ensure end date is after start date
          if (_endDate.isBefore(_startDate)) {
            _startDate = _endDate;
          }
        }
      });
    }
  }

  Future<void> _generateReport() async {
    setState(() {
      _isGenerating = true;
      _generatedReport = null;
    });

    try {
      final firebaseService = Provider.of<FirebaseService>(context, listen: false);

      // Fetch all students in the class
      final studentDocs = await firebaseService.getStudentsInClass(widget.classModel.id);
      final students = studentDocs
          .map((doc) => StudentModel.fromFirestore(doc))
          .toList();

      // Fetch reading logs for all students
      final allReadingLogs = <String, List<ReadingLogModel>>{};
      for (final student in students) {
        final logDocs = await firebaseService.getReadingLogsForStudent(
          student.id,
          startDate: _startDate,
          endDate: _endDate,
        );
        allReadingLogs[student.id] = logDocs
            .map((doc) => ReadingLogModel.fromFirestore(doc))
            .toList();
      }

      // Generate the PDF
      final reportFile = await _pdfService.generateClassReport(
        classModel: widget.classModel,
        students: students,
        allReadingLogs: allReadingLogs,
        startDate: _startDate,
        endDate: _endDate,
      );

      setState(() {
        _generatedReport = reportFile;
        _isGenerating = false;
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Class report generated successfully!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      setState(() {
        _isGenerating = false;
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error generating report: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _shareReport() async {
    if (_generatedReport == null) return;

    try {
      await _pdfService.sharePdf(_generatedReport!);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sharing report: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _printReport() async {
    if (_generatedReport == null) return;

    try {
      await _pdfService.printPdf(_generatedReport!);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error printing report: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
