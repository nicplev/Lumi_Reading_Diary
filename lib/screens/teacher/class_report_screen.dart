import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../../data/models/class_model.dart';
import '../../data/models/student_model.dart';
import '../../data/models/reading_log_model.dart';
import '../../services/pdf_report_service.dart';
import '../../services/firebase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/teacher_constants.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
import '../../core/widgets/lumi/lumi_skeleton.dart';
import '../../core/widgets/lumi/teacher_alert_banner.dart';
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
      backgroundColor: AppColors.teacherBackground,
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
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildClassCard(),
            const SizedBox(height: 20),
            _buildDateRangeSelector(),
            const SizedBox(height: 20),
            _buildReportPreview(),
            const SizedBox(height: 20),
            _buildActionButtons(),
            if (_generatedReport != null) ...[
              const SizedBox(height: 20),
              _buildGeneratedReportCard(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildClassCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.teacherGradient,
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusXL),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.classModel.name,
                      style: TeacherTypography.h2.copyWith(color: AppColors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Class Report',
                      style: TeacherTypography.bodyMedium.copyWith(
                        color: AppColors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.assessment_rounded,
                  size: 24,
                  color: AppColors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildHeroPill(Icons.school_rounded, 'Year ${widget.classModel.yearLevel ?? "N/A"}'),
              _buildHeroPill(Icons.room_rounded, 'Room ${widget.classModel.room ?? "N/A"}'),
              _buildHeroPill(Icons.people_alt_rounded, '${widget.classModel.studentIds.length} students'),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.05, end: 0, duration: 400.ms);
  }

  Widget _buildHeroPill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppColors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: TeacherTypography.bodySmall.copyWith(
              color: AppColors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateRangeSelector() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: TeacherDimensions.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('REPORT PERIOD', style: TeacherTypography.sectionHeader),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildDateButton(
                  label: 'Start Date',
                  date: _startDate,
                  icon: Icons.calendar_today_rounded,
                  onTap: () => _selectDate(context, isStartDate: true),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward_rounded, size: 16, color: AppColors.teacherPrimary),
              ),
              Expanded(
                child: _buildDateButton(
                  label: 'End Date',
                  date: _endDate,
                  icon: Icons.event_rounded,
                  onTap: () => _selectDate(context, isStartDate: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
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
    ).animate().fadeIn(delay: 100.ms, duration: 400.ms).slideY(begin: 0.03, end: 0, duration: 400.ms);
  }

  Widget _buildDateButton({
    required String label,
    required DateTime date,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.teacherSurfaceTint,
            border: Border.all(color: AppColors.teacherBorder),
            borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.teacherPrimaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: AppColors.teacherPrimary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TeacherTypography.caption),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('MMM dd, yyyy').format(date),
                      style: TeacherTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.charcoal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
      padding: const EdgeInsets.all(20),
      decoration: TeacherDimensions.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('REPORT CONTENTS', style: TeacherTypography.sectionHeader),
          const SizedBox(height: 14),
          if (_isGenerating)
            _buildPreviewSkeleton()
          else ...[
            _buildPreviewItem(
              icon: Icons.date_range_rounded,
              iconColor: AppColors.teacherPrimary,
              label: 'Period',
              value:
                  '${DateFormat('MMM dd').format(_startDate)} - ${DateFormat('MMM dd, yyyy').format(_endDate)}',
            ),
            _buildPreviewItem(
              icon: Icons.people_alt_rounded,
              iconColor: const Color(0xFF66BB6A),
              label: 'Students',
              value: '${widget.classModel.studentIds.length} students',
            ),
            _buildPreviewItem(
              icon: Icons.checklist_rounded,
              iconColor: AppColors.warmOrange,
              label: 'Includes',
              value:
                  'Class overview, engagement metrics, top performers, students needing support, trends',
            ),
            _buildPreviewItem(
              icon: Icons.picture_as_pdf_rounded,
              iconColor: const Color(0xFFEF5350),
              label: 'Format',
              value: 'PDF (A4)',
            ),
          ],
        ],
      ),
    ).animate().fadeIn(delay: 200.ms, duration: 400.ms).slideY(begin: 0.03, end: 0, duration: 400.ms);
  }

  Widget _buildPreviewSkeleton() {
    return Column(
      children: List.generate(4, (i) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            const LumiSkeleton(width: 40, height: 40, borderRadius: 12),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const LumiSkeleton(width: 60, height: 12),
                  const SizedBox(height: 6),
                  LumiSkeleton(width: i == 2 ? 200 : 120, height: 14),
                ],
              ),
            ),
          ],
        ),
      )),
    );
  }

  Widget _buildPreviewItem({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TeacherTypography.caption),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: TeacherTypography.bodyMedium.copyWith(
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
        LumiPrimaryButton(
          onPressed: _isGenerating ? null : _generateReport,
          text: _isGenerating ? 'Generating...' : 'Generate Class Report',
          icon: Icons.picture_as_pdf_rounded,
          isLoading: _isGenerating,
          isFullWidth: true,
          color: AppColors.teacherPrimary,
        ),
        if (_generatedReport != null) ...[
          const SizedBox(height: 12),
          LumiSecondaryButton(
            onPressed: _shareReport,
            text: 'Share Report',
            icon: Icons.share_rounded,
            isFullWidth: true,
            color: AppColors.teacherPrimary,
          ),
          const SizedBox(height: 8),
          LumiSecondaryButton(
            onPressed: _printReport,
            text: 'Print Report',
            icon: Icons.print_rounded,
            isFullWidth: true,
            color: AppColors.teacherPrimary,
          ),
        ],
      ],
    ).animate().fadeIn(delay: 300.ms, duration: 400.ms);
  }

  Widget _buildGeneratedReportCard() {
    return TeacherAlertBanner(
      type: AlertBannerType.success,
      message: 'Report generated! ${_generatedReport!.path.split('/').last}',
    ).animate().fadeIn(duration: 400.ms).slideY(
      begin: 0.05, end: 0, duration: 400.ms, curve: Curves.easeOutCubic,
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
      final firestore = FirebaseService.instance.firestore;
      final schoolId = widget.classModel.schoolId;

      // Fetch all students in the class
      final studentSnap = await firestore
          .collection('schools')
          .doc(schoolId)
          .collection('students')
          .where('classId', isEqualTo: widget.classModel.id)
          .where('isActive', isEqualTo: true)
          .get();
      final students = studentSnap.docs
          .map((doc) => StudentModel.fromFirestore(doc))
          .toList();

      // Fetch reading logs for all students
      final allReadingLogs = <String, List<ReadingLogModel>>{};
      for (final student in students) {
        final logSnap = await firestore
            .collection('schools')
            .doc(schoolId)
            .collection('readingLogs')
            .where('studentId', isEqualTo: student.id)
            .where('date',
                isGreaterThanOrEqualTo: Timestamp.fromDate(_startDate))
            .where('date',
                isLessThanOrEqualTo: Timestamp.fromDate(_endDate))
            .orderBy('date', descending: true)
            .get();
        allReadingLogs[student.id] = logSnap.docs
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
