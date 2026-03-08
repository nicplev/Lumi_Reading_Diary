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
import '../../core/theme/teacher_constants.dart';
import '../../core/widgets/lumi/teacher_filter_chip.dart';

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
  String _activeRange = 'Last Month';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Class Report',
          style: TextStyle(
            fontFamily: 'Nunito',
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: AppColors.teacherPrimary,
        foregroundColor: AppColors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildClassCard(),
            const SizedBox(height: 16),
            _buildDateRangeSelector(),
            const SizedBox(height: 16),
            _buildReportPreview(),
            const SizedBox(height: 16),
            _buildActionButtons(),
            if (_generatedReport != null) ...[
              const SizedBox(height: 16),
              _buildGeneratedReportCard(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildClassCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
        boxShadow: TeacherDimensions.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Class Information', style: TeacherTypography.bodySmall),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppColors.teacherPrimaryLight,
                  borderRadius:
                      BorderRadius.circular(TeacherDimensions.radiusM),
                ),
                child: Icon(Icons.class_,
                    size: 32, color: AppColors.teacherPrimary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.classModel.name,
                        style: TeacherTypography.h3),
                    const SizedBox(height: 4),
                    Text(
                      'Year ${widget.classModel.yearLevel ?? "N/A"} | Room ${widget.classModel.room ?? "N/A"}',
                      style: TeacherTypography.bodySmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${widget.classModel.studentIds.length} students',
                      style: TeacherTypography.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDateRangeSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
        boxShadow: TeacherDimensions.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Report Period', style: TeacherTypography.bodySmall),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildDateButton(
                  label: 'Start Date',
                  date: _startDate,
                  onTap: () => _selectDate(context, isStartDate: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDateButton(
                  label: 'End Date',
                  date: _endDate,
                  onTap: () => _selectDate(context, isStartDate: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildQuickRangeChip('Last Week', 7),
                const SizedBox(width: 8),
                _buildQuickRangeChip('Last Month', 30),
                const SizedBox(width: 8),
                _buildQuickRangeChip('Last Term', 90),
                const SizedBox(width: 8),
                _buildQuickRangeChip('This Year', null),
              ],
            ),
          ),
        ],
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
      borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.teacherPrimary),
          borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TeacherTypography.bodySmall),
            const SizedBox(height: 4),
            Text(
              DateFormat('MMM dd, yyyy').format(date),
              style: TeacherTypography.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickRangeChip(String label, int? days) {
    final isActive = _activeRange == label;
    return TeacherFilterChip(
      label: label,
      isActive: isActive,
      onTap: () {
        setState(() {
          _activeRange = label;
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
        boxShadow: TeacherDimensions.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.preview, color: AppColors.teacherPrimary, size: 20),
              const SizedBox(width: 8),
              Text('Report Preview', style: TeacherTypography.h3),
            ],
          ),
          const SizedBox(height: 12),
          _buildPreviewItem(
            icon: Icons.calendar_today,
            label: 'Period',
            value:
                '${DateFormat('MMM dd').format(_startDate)} - ${DateFormat('MMM dd, yyyy').format(_endDate)}',
          ),
          Divider(color: AppColors.divider),
          _buildPreviewItem(
            icon: Icons.people,
            label: 'Students',
            value: '${widget.classModel.studentIds.length} students',
          ),
          Divider(color: AppColors.divider),
          _buildPreviewItem(
            icon: Icons.description,
            label: 'Includes',
            value:
                'Class overview, engagement metrics, top performers, students needing support, trends',
          ),
          Divider(color: AppColors.divider),
          _buildPreviewItem(
            icon: Icons.format_size,
            label: 'Format',
            value: 'PDF (A4)',
          ),
        ],
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
          Icon(icon, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TeacherTypography.bodySmall),
                Text(value, style: TeacherTypography.bodyMedium),
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
        SizedBox(
          height: 48,
          child: ElevatedButton.icon(
            onPressed: _isGenerating ? null : _generateReport,
            icon: _isGenerating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.white))
                : const Icon(Icons.picture_as_pdf),
            label: Text(
              _isGenerating ? 'Generating...' : 'Generate Class Report',
              style: TeacherTypography.buttonText,
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.teacherPrimary,
              foregroundColor: AppColors.white,
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(TeacherDimensions.radiusM),
              ),
              elevation: 0,
            ),
          ),
        ),
        if (_generatedReport != null) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _shareReport,
              icon: const Icon(Icons.share),
              label: Text('Share Report',
                  style: TeacherTypography.buttonText
                      .copyWith(color: AppColors.teacherPrimary)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.teacherPrimary,
                side: BorderSide(color: AppColors.teacherPrimary),
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(TeacherDimensions.radiusM),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _printReport,
              icon: const Icon(Icons.print),
              label: Text('Print Report',
                  style: TeacherTypography.buttonText
                      .copyWith(color: AppColors.teacherPrimary)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.teacherPrimary,
                side: BorderSide(color: AppColors.teacherPrimary),
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(TeacherDimensions.radiusM),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildGeneratedReportCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
        border: Border.all(
            color: AppColors.success.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: AppColors.success, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Report Generated Successfully!',
                    style: TeacherTypography.bodyMedium
                        .copyWith(fontWeight: FontWeight.w600)),
                Text(
                  'Saved to: ${_generatedReport!.path.split('/').last}',
                  style: TeacherTypography.bodySmall,
                ),
              ],
            ),
          ),
        ],
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
          if (_startDate.isAfter(_endDate)) {
            _endDate = _startDate;
          }
        } else {
          _endDate = picked;
          if (_endDate.isBefore(_startDate)) {
            _startDate = _endDate;
          }
        }
        _activeRange = ''; // Deselect quick range
      });
    }
  }

  Future<void> _generateReport() async {
    setState(() {
      _isGenerating = true;
      _generatedReport = null;
    });

    try {
      final firebaseService =
          Provider.of<FirebaseService>(context, listen: false);

      // Fetch all students in the class
      final studentDocs =
          await firebaseService.getStudentsInClass(widget.classModel.id);
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
          backgroundColor: AppColors.success,
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
          backgroundColor: AppColors.error,
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
          backgroundColor: AppColors.error,
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
          backgroundColor: AppColors.error,
        ),
      );
    }
  }
}
