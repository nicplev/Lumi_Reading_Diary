import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
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

/// Screen for generating and sharing student progress reports
/// Used by both parents and teachers
class StudentReportScreen extends StatefulWidget {
  final StudentModel student;

  const StudentReportScreen({
    super.key,
    required this.student,
  });

  @override
  State<StudentReportScreen> createState() => _StudentReportScreenState();
}

class _StudentReportScreenState extends State<StudentReportScreen> {
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
        title: Text('Generate Report', style: LumiTextStyles.h3()),
        backgroundColor: AppColors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: LumiPadding.allS,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStudentCard(),
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

  Widget _buildStudentCard() {
    return LumiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Student Information',
            style: LumiTextStyles.h3(),
          ),
          LumiGap.xs,
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: AppColors.rosePink.withValues(alpha: 0.1),
                child: Text(
                  widget.student.firstName[0].toUpperCase(),
                  style: LumiTextStyles.h2(
                    color: AppColors.rosePink,
                  ),
                ),
              ),
              LumiGap.horizontalS,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.student.fullName,
                      style: LumiTextStyles.h2(),
                    ),
                    LumiGap.xxs,
                    Text(
                      'Reading Level: ${widget.student.currentReadingLevel ?? "Not set"}',
                      style: LumiTextStyles.body(
                        color: AppColors.charcoal.withValues(alpha: 0.6),
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
            style: LumiTextStyles.h3(),
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
              LumiGap.horizontalS,
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
            spacing: LumiSpacing.xs,
            runSpacing: LumiSpacing.xs,
            children: [
              _buildQuickRangeChip('Last 7 Days', 7),
              _buildQuickRangeChip('Last 30 Days', 30),
              _buildQuickRangeChip('Last 90 Days', 90),
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
      borderRadius: LumiBorders.small,
      child: Container(
        padding: LumiPadding.allXS,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.rosePink),
          borderRadius: LumiBorders.small,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: LumiTextStyles.bodySmall(
                color: AppColors.charcoal.withValues(alpha: 0.6),
              ),
            ),
            LumiGap.xxs,
            Text(
              DateFormat('MMM dd, yyyy').format(date),
              style: LumiTextStyles.bodyLarge(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickRangeChip(String label, int? days) {
    return ActionChip(
      label: Text(label),
      backgroundColor: AppColors.white,
      side: BorderSide(
        color: AppColors.charcoal.withValues(alpha: 0.3),
      ),
      labelStyle: LumiTextStyles.label(),
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
              Icon(Icons.preview, color: AppColors.rosePink),
              LumiGap.horizontalXS,
              Text(
                'Report Preview',
                style: LumiTextStyles.h3(),
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
          const Divider(),
          _buildPreviewItem(
            icon: Icons.access_time,
            label: 'Duration',
            value: '${_endDate.difference(_startDate).inDays} days',
          ),
          const Divider(),
          _buildPreviewItem(
            icon: Icons.description,
            label: 'Includes',
            value: 'Reading stats, trends, books, achievements',
          ),
          const Divider(),
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
      padding: EdgeInsets.symmetric(vertical: LumiSpacing.xs),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: AppColors.charcoal.withValues(alpha: 0.6),
          ),
          LumiGap.horizontalXS,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: LumiTextStyles.bodySmall(
                    color: AppColors.charcoal.withValues(alpha: 0.6),
                  ),
                ),
                Text(
                  value,
                  style: LumiTextStyles.body(),
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
        if (_isGenerating)
          Container(
            padding: LumiPadding.allM,
            decoration: BoxDecoration(
              color: AppColors.rosePink.withValues(alpha: 0.1),
              borderRadius: LumiBorders.large,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.rosePink,
                  ),
                ),
                LumiGap.horizontalS,
                Text(
                  'Generating...',
                  style: LumiTextStyles.bodyLarge(
                    color: AppColors.rosePink,
                  ),
                ),
              ],
            ),
          )
        else
          LumiPrimaryButton(
            onPressed: _generateReport,
            text: 'Generate Report',
            icon: Icons.picture_as_pdf,
          ),
        if (_generatedReport != null) ...[
          LumiGap.s,
          LumiSecondaryButton(
            onPressed: _shareReport,
            text: 'Share Report',
            icon: Icons.share,
          ),
          LumiGap.xs,
          LumiSecondaryButton(
            onPressed: _printReport,
            text: 'Print Report',
            icon: Icons.print,
          ),
        ],
      ],
    );
  }

  Widget _buildGeneratedReportCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.1),
        borderRadius: LumiBorders.large,
      ),
      child: LumiCard(
        padding: EdgeInsets.zero,
        child: Padding(
          padding: LumiPadding.allS,
          child: Row(
            children: [
              Icon(Icons.check_circle, color: AppColors.success, size: 32),
              LumiGap.horizontalS,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Report Generated Successfully!',
                      style: LumiTextStyles.h3(
                        color: AppColors.success,
                      ),
                    ),
                    LumiGap.xxs,
                    Text(
                      'Saved to: ${_generatedReport!.path.split('/').last}',
                      style: LumiTextStyles.bodySmall(
                        color: AppColors.success.withValues(alpha: 0.8),
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
      // Fetch reading logs for the date range
      final firebaseService =
          Provider.of<FirebaseService>(context, listen: false);
      final docs = await firebaseService.getReadingLogsForStudent(
        widget.student.id,
        startDate: _startDate,
        endDate: _endDate,
      );

      // Convert documents to ReadingLogModel objects
      final readingLogs =
          docs.map((doc) => ReadingLogModel.fromFirestore(doc)).toList();

      // Optionally fetch class average for comparison
      // This would require additional Firebase query
      // For now, we'll skip class average

      // Generate the PDF
      final reportFile = await _pdfService.generateStudentReport(
        student: widget.student,
        readingLogs: readingLogs,
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
          content: const Text('Report generated successfully!'),
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
