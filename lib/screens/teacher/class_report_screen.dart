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
import '../../core/theme/lumi_text_styles.dart';
import '../../core/theme/lumi_spacing.dart';
import '../../core/theme/lumi_borders.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
import '../../core/widgets/lumi/lumi_card.dart';

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
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        title: Text(
          'Class Report',
          style: LumiTextStyles.h3(color: AppColors.white),
        ),
        backgroundColor: AppColors.rosePink,
        iconTheme: const IconThemeData(color: AppColors.white),
      ),
      body: SingleChildScrollView(
        padding: LumiPadding.allS,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildClassCard(),
            LumiGap.m,
            _buildDateRangeSelector(),
            LumiGap.m,
            _buildReportPreview(),
            LumiGap.m,
            _buildActionButtons(),
            if (_generatedReport != null) ...[
              LumiGap.m,
              _buildGeneratedReportCard(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildClassCard() {
    return LumiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Class Information',
            style: LumiTextStyles.bodyMedium(color: AppColors.charcoal),
          ),
          LumiGap.s,
          Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppColors.rosePink.withValues(alpha: 0.1),
                  borderRadius: LumiBorders.medium,
                ),
                child: const Icon(
                  Icons.class_,
                  size: 32,
                  color: AppColors.rosePink,
                ),
              ),
              LumiGap.s,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.classModel.name,
                      style: LumiTextStyles.h3(color: AppColors.charcoal),
                    ),
                    LumiGap.xxs,
                    Text(
                      'Year ${widget.classModel.yearLevel ?? "N/A"} | Room ${widget.classModel.room ?? "N/A"}',
                      style: LumiTextStyles.body(
                        color: AppColors.charcoal.withValues(alpha: 0.7),
                      ),
                    ),
                    LumiGap.xxs,
                    Text(
                      '${widget.classModel.studentIds.length} students',
                      style: LumiTextStyles.bodySmall(
                        color: AppColors.charcoal.withValues(alpha: 0.7),
                      ),
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
    return LumiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Report Period',
            style: LumiTextStyles.bodyMedium(color: AppColors.charcoal),
          ),
          LumiGap.s,
          Row(
            children: [
              Expanded(
                child: _buildDateButton(
                  label: 'Start Date',
                  date: _startDate,
                  onTap: () => _selectDate(context, isStartDate: true),
                ),
              ),
              LumiGap.s,
              Expanded(
                child: _buildDateButton(
                  label: 'End Date',
                  date: _endDate,
                  onTap: () => _selectDate(context, isStartDate: false),
                ),
              ),
            ],
          ),
          LumiGap.s,
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
    );
  }

  Widget _buildDateButton({
    required String label,
    required DateTime date,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: LumiBorders.medium,
      child: Container(
        padding: LumiPadding.allXS,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.rosePink),
          borderRadius: LumiBorders.medium,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: LumiTextStyles.bodySmall(
                color: AppColors.charcoal.withValues(alpha: 0.7),
              ),
            ),
            LumiGap.xxs,
            Text(
              DateFormat('MMM dd, yyyy').format(date),
              style: LumiTextStyles.bodyMedium(color: AppColors.charcoal),
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
    return LumiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.preview, color: AppColors.rosePink),
              LumiGap.horizontalXS,
              Text(
                'Report Preview',
                style: LumiTextStyles.bodyMedium(color: AppColors.charcoal),
              ),
            ],
          ),
          LumiGap.s,
          _buildPreviewItem(
            icon: Icons.calendar_today,
            label: 'Period',
            value:
                '${DateFormat('MMM dd').format(_startDate)} - ${DateFormat('MMM dd, yyyy').format(_endDate)}',
          ),
          Divider(color: AppColors.charcoal.withValues(alpha: 0.2)),
          _buildPreviewItem(
            icon: Icons.people,
            label: 'Students',
            value: '${widget.classModel.studentIds.length} students',
          ),
          Divider(color: AppColors.charcoal.withValues(alpha: 0.2)),
          _buildPreviewItem(
            icon: Icons.description,
            label: 'Includes',
            value:
                'Class overview, engagement metrics, top performers, students needing support, trends',
          ),
          Divider(color: AppColors.charcoal.withValues(alpha: 0.2)),
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
      padding: LumiPadding.verticalXS,
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: AppColors.charcoal.withValues(alpha: 0.7),
          ),
          LumiGap.horizontalXS,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: LumiTextStyles.bodySmall(
                    color: AppColors.charcoal.withValues(alpha: 0.7),
                  ),
                ),
                Text(
                  value,
                  style: LumiTextStyles.bodyMedium(color: AppColors.charcoal),
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
          icon: Icons.picture_as_pdf,
          isLoading: _isGenerating,
          isFullWidth: true,
        ),
        if (_generatedReport != null) ...[
          LumiGap.s,
          LumiSecondaryButton(
            onPressed: _shareReport,
            text: 'Share Report',
            icon: Icons.share,
            isFullWidth: true,
          ),
          LumiGap.xs,
          LumiSecondaryButton(
            onPressed: _printReport,
            text: 'Print Report',
            icon: Icons.print,
            isFullWidth: true,
          ),
        ],
      ],
    );
  }

  Widget _buildGeneratedReportCard() {
    return LumiInfoCard(
      type: LumiInfoCardType.success,
      title: 'Report Generated Successfully!',
      message: 'Saved to: ${_generatedReport!.path.split('/').last}',
      icon: Icons.check_circle,
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
        SnackBar(
          content: Text(
            'Class report generated successfully!',
            style: LumiTextStyles.body(color: AppColors.white),
          ),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      setState(() {
        _isGenerating = false;
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error generating report: $e',
            style: LumiTextStyles.body(color: AppColors.white),
          ),
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
          content: Text(
            'Error sharing report: $e',
            style: LumiTextStyles.body(color: AppColors.white),
          ),
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
          content: Text(
            'Error printing report: $e',
            style: LumiTextStyles.body(color: AppColors.white),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }
}
