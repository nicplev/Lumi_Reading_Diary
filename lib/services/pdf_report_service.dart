import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../data/models/student_model.dart';
import '../data/models/reading_log_model.dart';
import '../data/models/class_model.dart';

/// Service for generating professional PDF reports
/// Supports student progress reports and class summary reports
class PdfReportService {
  /// Generate a comprehensive student progress report
  ///
  /// [student] - Student to generate report for
  /// [readingLogs] - Reading logs for the date range
  /// [startDate] - Report start date
  /// [endDate] - Report end date
  /// [classAverage] - Optional class average for comparison
  Future<File> generateStudentReport({
    required StudentModel student,
    required List<ReadingLogModel> readingLogs,
    required DateTime startDate,
    required DateTime endDate,
    double? classAverage,
  }) async {
    final pdf = pw.Document();

    // Calculate report metrics
    final metrics = _calculateStudentMetrics(readingLogs, startDate, endDate);

    // Add pages to PDF
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => [
          _buildReportHeader(student, startDate, endDate),
          pw.SizedBox(height: 20),
          _buildStudentInfo(student),
          pw.SizedBox(height: 20),
          _buildMetricsSummary(metrics, classAverage),
          pw.SizedBox(height: 20),
          _buildReadingTrend(metrics),
          pw.SizedBox(height: 20),
          _buildBooksList(readingLogs),
          pw.SizedBox(height: 20),
          _buildRecommendations(metrics, student),
          pw.SizedBox(height: 20),
          _buildAchievements(student),
          pw.Spacer(),
          _buildReportFooter(),
        ],
      ),
    );

    // Save PDF to file
    final output = await _savePdfToFile(
      pdf,
      'student_report_${student.id}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );

    return output;
  }

  /// Generate a class summary report
  ///
  /// [classModel] - Class to generate report for
  /// [students] - All students in the class
  /// [allReadingLogs] - All reading logs for the date range
  /// [startDate] - Report start date
  /// [endDate] - Report end date
  Future<File> generateClassReport({
    required ClassModel classModel,
    required List<StudentModel> students,
    required Map<String, List<ReadingLogModel>> allReadingLogs,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final pdf = pw.Document();

    // Calculate class metrics
    final classMetrics = _calculateClassMetrics(
      students,
      allReadingLogs,
      startDate,
      endDate,
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => [
          _buildClassReportHeader(classModel, startDate, endDate),
          pw.SizedBox(height: 20),
          _buildClassOverview(classMetrics, students.length),
          pw.SizedBox(height: 20),
          _buildEngagementMetrics(classMetrics),
          pw.SizedBox(height: 20),
          _buildTopPerformers(classMetrics),
          pw.SizedBox(height: 20),
          _buildStudentsNeedingSupport(classMetrics),
          pw.SizedBox(height: 20),
          _buildClassTrends(classMetrics),
          pw.Spacer(),
          _buildReportFooter(),
        ],
      ),
    );

    final output = await _savePdfToFile(
      pdf,
      'class_report_${classModel.id}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );

    return output;
  }

  // ==================== STUDENT REPORT BUILDERS ====================

  pw.Widget _buildReportHeader(
    StudentModel student,
    DateTime startDate,
    DateTime endDate,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue50,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Lumi Reading Diary',
            style: pw.TextStyle(
              fontSize: 24,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue900,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Student Progress Report',
            style: pw.TextStyle(
              fontSize: 18,
              color: PdfColors.blue700,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Report Period: ${DateFormat('MMM dd, yyyy').format(startDate)} - ${DateFormat('MMM dd, yyyy').format(endDate)}',
            style: const pw.TextStyle(
              fontSize: 12,
              color: PdfColors.grey700,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildStudentInfo(StudentModel student) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Student Information',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            children: [
              pw.Expanded(
                child: _buildInfoRow('Name:', student.fullName),
              ),
              pw.Expanded(
                child: _buildInfoRow(
                  'Reading Level:',
                  student.currentReadingLevel ?? 'Not set',
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            children: [
              pw.Expanded(
                child: _buildInfoRow(
                  'Student ID:',
                  student.studentId ?? 'N/A',
                ),
              ),
              pw.Expanded(
                child: _buildInfoRow(
                  'Enrolled:',
                  student.enrolledAt != null
                      ? DateFormat('MMM dd, yyyy').format(student.enrolledAt!)
                      : 'N/A',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildInfoRow(String label, String value) {
    return pw.Row(
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            fontSize: 10,
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Text(
          value,
          style: const pw.TextStyle(fontSize: 10),
        ),
      ],
    );
  }

  pw.Widget _buildMetricsSummary(
    Map<String, dynamic> metrics,
    double? classAverage,
  ) {
    return pw.Container(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Performance Summary',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            children: [
              pw.Expanded(
                child: _buildMetricCard(
                  'Total Minutes',
                  '${metrics['totalMinutes']}',
                  'min',
                  PdfColors.green,
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: _buildMetricCard(
                  'Reading Days',
                  '${metrics['readingDays']}',
                  'days',
                  PdfColors.blue,
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: _buildMetricCard(
                  'Books Read',
                  '${metrics['booksRead']}',
                  'books',
                  PdfColors.purple,
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: _buildMetricCard(
                  'Current Streak',
                  '${metrics['currentStreak']}',
                  'days',
                  PdfColors.orange,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            children: [
              pw.Expanded(
                child: _buildMetricCard(
                  'Avg. Minutes/Day',
                  '${metrics['avgMinutesPerDay'].toStringAsFixed(1)}',
                  'min',
                  PdfColors.teal,
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: _buildMetricCard(
                  'Target Met',
                  '${metrics['targetMetPercentage'].toStringAsFixed(0)}%',
                  'of days',
                  PdfColors.indigo,
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: _buildMetricCard(
                  'Longest Streak',
                  '${metrics['longestStreak']}',
                  'days',
                  PdfColors.pink,
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: classAverage != null
                    ? _buildMetricCard(
                        'vs Class Avg',
                        '${((metrics['avgMinutesPerDay'] / classAverage - 1) * 100).toStringAsFixed(0)}%',
                        metrics['avgMinutesPerDay'] > classAverage
                            ? 'above'
                            : 'below',
                        metrics['avgMinutesPerDay'] > classAverage
                            ? PdfColors.green
                            : PdfColors.amber,
                      )
                    : pw.Container(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildMetricCard(
    String label,
    String value,
    String unit,
    PdfColor color,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: color.shade(0.1),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        border: pw.Border.all(color: color),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 8,
              color: PdfColors.grey700,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
              color: color.shade(0.8),
            ),
          ),
          pw.Text(
            unit,
            style: pw.TextStyle(
              fontSize: 8,
              color: PdfColors.grey600,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildReadingTrend(Map<String, dynamic> metrics) {
    final weeklyData = metrics['weeklyData'] as List<Map<String, dynamic>>;

    return pw.Container(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Weekly Reading Trend',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Container(
            height: 150,
            child: _buildSimpleBarChart(weeklyData),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildSimpleBarChart(List<Map<String, dynamic>> weeklyData) {
    if (weeklyData.isEmpty) {
      return pw.Center(
        child: pw.Text('No data available'),
      );
    }

    final maxMinutes = weeklyData
        .map((e) => e['minutes'] as int)
        .reduce((a, b) => a > b ? a : b)
        .toDouble();

    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: weeklyData.map((data) {
        final minutes = (data['minutes'] as int).toDouble();
        final height = maxMinutes > 0 ? (minutes / maxMinutes) * 130 : 0.0;

        return pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          children: [
            pw.Text(
              '$minutes',
              style: const pw.TextStyle(fontSize: 8),
            ),
            pw.SizedBox(height: 4),
            pw.Container(
              width: 40,
              height: height,
              decoration: pw.BoxDecoration(
                color: PdfColors.blue,
                borderRadius: const pw.BorderRadius.vertical(
                  top: pw.Radius.circular(4),
                ),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              data['label'] as String,
              style: const pw.TextStyle(fontSize: 8),
            ),
          ],
        );
      }).toList(),
    );
  }

  pw.Widget _buildBooksList(List<ReadingLogModel> readingLogs) {
    // Extract all unique books
    final books = <String>{};
    for (final log in readingLogs) {
      books.addAll(log.bookTitles);
    }

    return pw.Container(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Books Read (${books.length})',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            child: pw.Wrap(
              spacing: 8,
              runSpacing: 8,
              children: books.take(20).map((book) {
                return pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.blue50,
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(4),
                    ),
                  ),
                  child: pw.Text(
                    book,
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                );
              }).toList(),
            ),
          ),
          if (books.length > 20)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 8),
              child: pw.Text(
                '...and ${books.length - 20} more books',
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  pw.Widget _buildRecommendations(
    Map<String, dynamic> metrics,
    StudentModel student,
  ) {
    final recommendations = _generateRecommendations(metrics, student);

    return pw.Container(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Recommendations & Next Steps',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 12),
          ...recommendations.map((rec) {
            return pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    width: 6,
                    height: 6,
                    margin: const pw.EdgeInsets.only(top: 4, right: 8),
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.blue,
                      shape: pw.BoxShape.circle,
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      rec,
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  pw.Widget _buildAchievements(StudentModel student) {
    // Note: This would integrate with the achievement system
    // For now, showing basic milestone achievements
    final achievements = <String>[];

    if (student.stats != null) {
      final stats = student.stats!;

      if (stats.totalMinutesRead >= 600) {
        achievements.add('🏆 10 Hour Club - Read for 600+ minutes');
      }
      if (stats.currentStreak >= 7) {
        achievements.add('🔥 Week Warrior - 7 day reading streak');
      }
      if (stats.totalBooksRead >= 10) {
        achievements.add('📚 Book Collector - Read 10+ books');
      }
      if (stats.longestStreak >= 30) {
        achievements.add('💎 Monthly Master - 30 day streak achieved');
      }
    }

    if (achievements.isEmpty) {
      return pw.Container();
    }

    return pw.Container(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Achievements Unlocked',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.amber50,
              border: pw.Border.all(color: PdfColors.amber),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: achievements.map((achievement) {
                return pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Text(
                    achievement,
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== CLASS REPORT BUILDERS ====================

  pw.Widget _buildClassReportHeader(
    ClassModel classModel,
    DateTime startDate,
    DateTime endDate,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: PdfColors.purple50,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Lumi Reading Diary',
            style: pw.TextStyle(
              fontSize: 24,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.purple900,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Class Summary Report',
            style: pw.TextStyle(
              fontSize: 18,
              color: PdfColors.purple700,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Class: ${classModel.name}${classModel.yearLevel != null ? " | Year ${classModel.yearLevel}" : ""}',
            style: const pw.TextStyle(
              fontSize: 12,
              color: PdfColors.grey700,
            ),
          ),
          pw.Text(
            'Report Period: ${DateFormat('MMM dd, yyyy').format(startDate)} - ${DateFormat('MMM dd, yyyy').format(endDate)}',
            style: const pw.TextStyle(
              fontSize: 12,
              color: PdfColors.grey700,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildClassOverview(
    Map<String, dynamic> classMetrics,
    int totalStudents,
  ) {
    return pw.Container(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Class Overview',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            children: [
              pw.Expanded(
                child: _buildMetricCard(
                  'Total Students',
                  '$totalStudents',
                  'students',
                  PdfColors.blue,
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: _buildMetricCard(
                  'Active Readers',
                  '${classMetrics['activeReaders']}',
                  'students',
                  PdfColors.green,
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: _buildMetricCard(
                  'Engagement Rate',
                  '${classMetrics['engagementRate'].toStringAsFixed(0)}%',
                  'participation',
                  PdfColors.purple,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildEngagementMetrics(Map<String, dynamic> classMetrics) {
    return pw.Container(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Reading Metrics',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            children: [
              pw.Expanded(
                child: _buildMetricCard(
                  'Total Minutes',
                  '${classMetrics['totalMinutes']}',
                  'min',
                  PdfColors.green,
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: _buildMetricCard(
                  'Avg. Per Student',
                  '${classMetrics['avgMinutesPerStudent'].toStringAsFixed(0)}',
                  'min',
                  PdfColors.blue,
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: _buildMetricCard(
                  'Total Books',
                  '${classMetrics['totalBooks']}',
                  'books',
                  PdfColors.purple,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildTopPerformers(Map<String, dynamic> classMetrics) {
    final topPerformers =
        classMetrics['topPerformers'] as List<Map<String, dynamic>>;

    if (topPerformers.isEmpty) {
      return pw.Container();
    }

    return pw.Container(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Top Performers (by reading time)',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            children: [
              // Header
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.blue50),
                children: [
                  _buildTableCell('Rank', isHeader: true),
                  _buildTableCell('Student Name', isHeader: true),
                  _buildTableCell('Minutes Read', isHeader: true),
                  _buildTableCell('Reading Days', isHeader: true),
                  _buildTableCell('Current Streak', isHeader: true),
                ],
              ),
              // Data rows
              ...topPerformers.take(10).toList().asMap().entries.map((entry) {
                final index = entry.key;
                final student = entry.value;
                return pw.TableRow(
                  children: [
                    _buildTableCell('${index + 1}'),
                    _buildTableCell(student['name'] as String),
                    _buildTableCell('${student['minutes']}'),
                    _buildTableCell('${student['days']}'),
                    _buildTableCell('${student['streak']}'),
                  ],
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildStudentsNeedingSupport(Map<String, dynamic> classMetrics) {
    final needsSupport =
        classMetrics['needsSupport'] as List<Map<String, dynamic>>;

    if (needsSupport.isEmpty) {
      return pw.Container(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Students Needing Support',
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.green50,
                border: pw.Border.all(color: PdfColors.green),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Text(
                '✓ All students are actively engaged in reading!',
                style: const pw.TextStyle(fontSize: 10),
              ),
            ),
          ],
        ),
      );
    }

    return pw.Container(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Students Needing Support',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            children: [
              // Header
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.amber50),
                children: [
                  _buildTableCell('Student Name', isHeader: true),
                  _buildTableCell('Minutes Read', isHeader: true),
                  _buildTableCell('Reading Days', isHeader: true),
                  _buildTableCell('Issue', isHeader: true),
                ],
              ),
              // Data rows
              ...needsSupport.take(10).map((student) {
                return pw.TableRow(
                  children: [
                    _buildTableCell(student['name'] as String),
                    _buildTableCell('${student['minutes']}'),
                    _buildTableCell('${student['days']}'),
                    _buildTableCell(student['issue'] as String),
                  ],
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildClassTrends(Map<String, dynamic> classMetrics) {
    return pw.Container(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Class Trends & Insights',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _buildInsightRow(
                  'Average Daily Reading Time:',
                  '${classMetrics['avgDailyMinutes'].toStringAsFixed(1)} minutes per student',
                ),
                pw.SizedBox(height: 8),
                _buildInsightRow(
                  'Students Meeting Daily Target:',
                  '${classMetrics['studentsMetTarget']} (${classMetrics['targetMetPercentage'].toStringAsFixed(0)}%)',
                ),
                pw.SizedBox(height: 8),
                _buildInsightRow(
                  'Longest Class Streak:',
                  '${classMetrics['longestStreak']} days',
                ),
                pw.SizedBox(height: 8),
                _buildInsightRow(
                  'Most Popular Reading Level:',
                  classMetrics['popularLevel'] ?? 'Not available',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildTableCell(String text, {bool isHeader = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  pw.Widget _buildInsightRow(String label, String value) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: 200,
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            value,
            style: const pw.TextStyle(fontSize: 10),
          ),
        ),
      ],
    );
  }

  pw.Widget _buildReportFooter() {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 16),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColors.grey300),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Generated by Lumi Reading Diary',
            style: const pw.TextStyle(
              fontSize: 8,
              color: PdfColors.grey600,
            ),
          ),
          pw.Text(
            'Report Date: ${DateFormat('MMM dd, yyyy').format(DateTime.now())}',
            style: const pw.TextStyle(
              fontSize: 8,
              color: PdfColors.grey600,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== HELPER METHODS ====================

  Map<String, dynamic> _calculateStudentMetrics(
    List<ReadingLogModel> readingLogs,
    DateTime startDate,
    DateTime endDate,
  ) {
    if (readingLogs.isEmpty) {
      return {
        'totalMinutes': 0,
        'readingDays': 0,
        'booksRead': 0,
        'currentStreak': 0,
        'longestStreak': 0,
        'avgMinutesPerDay': 0.0,
        'targetMetPercentage': 0.0,
        'weeklyData': <Map<String, dynamic>>[],
      };
    }

    // Sort logs by date
    final sortedLogs = List<ReadingLogModel>.from(readingLogs)
      ..sort((a, b) => a.date.compareTo(b.date));

    // Calculate basic metrics
    final totalMinutes = sortedLogs.fold<int>(
      0,
      (sum, log) => sum + log.minutesRead,
    );

    final readingDays = sortedLogs
        .where((log) => log.minutesRead > 0)
        .map((log) => DateFormat('yyyy-MM-dd').format(log.date))
        .toSet()
        .length;

    final allBooks = <String>{};
    for (final log in sortedLogs) {
      allBooks.addAll(log.bookTitles);
    }

    // Calculate streaks
    final streaks = _calculateStreaks(sortedLogs);

    // Calculate target met percentage
    final targetMetDays = sortedLogs.where((log) => log.hasMetTarget).length;
    final targetMetPercentage =
        sortedLogs.isNotEmpty ? (targetMetDays / sortedLogs.length) * 100 : 0.0;

    // Calculate weekly data for trend chart
    final weeklyData = _calculateWeeklyData(sortedLogs, startDate, endDate);

    // Average minutes per reading day (not per calendar day)
    final avgMinutesPerDay = readingDays > 0 ? totalMinutes / readingDays : 0.0;

    return {
      'totalMinutes': totalMinutes,
      'readingDays': readingDays,
      'booksRead': allBooks.length,
      'currentStreak': streaks['current'],
      'longestStreak': streaks['longest'],
      'avgMinutesPerDay': avgMinutesPerDay,
      'targetMetPercentage': targetMetPercentage,
      'weeklyData': weeklyData,
    };
  }

  Map<String, dynamic> _calculateClassMetrics(
    List<StudentModel> students,
    Map<String, List<ReadingLogModel>> allReadingLogs,
    DateTime startDate,
    DateTime endDate,
  ) {
    int totalMinutes = 0;
    int totalBooks = 0;
    int activeReaders = 0;
    int studentsMetTarget = 0;
    int longestStreak = 0;
    final levelCount = <String, int>{};

    final topPerformers = <Map<String, dynamic>>[];
    final needsSupport = <Map<String, dynamic>>[];

    for (final student in students) {
      final logs = allReadingLogs[student.id] ?? [];
      if (logs.isEmpty) {
        needsSupport.add({
          'name': student.fullName,
          'minutes': 0,
          'days': 0,
          'issue': 'No reading logged',
        });
        continue;
      }

      final metrics = _calculateStudentMetrics(logs, startDate, endDate);
      totalMinutes += metrics['totalMinutes'] as int;
      totalBooks += metrics['booksRead'] as int;

      final studentMinutes = metrics['totalMinutes'] as int;
      final readingDays = metrics['readingDays'] as int;

      if (studentMinutes > 0) activeReaders++;

      // Track reading levels
      if (student.currentReadingLevel != null) {
        levelCount[student.currentReadingLevel!] =
            (levelCount[student.currentReadingLevel!] ?? 0) + 1;
      }

      // Check if student met target most of the time
      final targetMetPct = metrics['targetMetPercentage'] as double;
      if (targetMetPct >= 70) studentsMetTarget++;

      // Track longest streak
      final studentStreak = metrics['longestStreak'] as int;
      if (studentStreak > longestStreak) longestStreak = studentStreak;

      // Add to top performers list
      topPerformers.add({
        'name': student.fullName,
        'minutes': studentMinutes,
        'days': readingDays,
        'streak': metrics['currentStreak'],
      });

      // Identify students needing support
      if (readingDays < 3) {
        needsSupport.add({
          'name': student.fullName,
          'minutes': studentMinutes,
          'days': readingDays,
          'issue': 'Low engagement',
        });
      } else if (targetMetPct < 50) {
        needsSupport.add({
          'name': student.fullName,
          'minutes': studentMinutes,
          'days': readingDays,
          'issue': 'Not meeting targets',
        });
      }
    }

    // Sort top performers by minutes
    topPerformers
        .sort((a, b) => (b['minutes'] as int).compareTo(a['minutes'] as int));

    // Find most popular reading level
    String? popularLevel;
    int maxCount = 0;
    levelCount.forEach((level, count) {
      if (count > maxCount) {
        maxCount = count;
        popularLevel = level;
      }
    });

    final engagementRate =
        students.isNotEmpty ? (activeReaders / students.length) * 100 : 0.0;
    final avgMinutesPerStudent =
        students.isNotEmpty ? totalMinutes / students.length : 0.0;
    final avgDailyMinutes =
        activeReaders > 0 ? totalMinutes / activeReaders : 0.0;
    final targetMetPercentage =
        students.isNotEmpty ? (studentsMetTarget / students.length) * 100 : 0.0;

    return {
      'totalMinutes': totalMinutes,
      'totalBooks': totalBooks,
      'activeReaders': activeReaders,
      'engagementRate': engagementRate,
      'avgMinutesPerStudent': avgMinutesPerStudent,
      'avgDailyMinutes': avgDailyMinutes,
      'studentsMetTarget': studentsMetTarget,
      'targetMetPercentage': targetMetPercentage,
      'longestStreak': longestStreak,
      'popularLevel': popularLevel,
      'topPerformers': topPerformers,
      'needsSupport': needsSupport,
    };
  }

  Map<String, int> _calculateStreaks(List<ReadingLogModel> sortedLogs) {
    if (sortedLogs.isEmpty) return {'current': 0, 'longest': 0};

    int currentStreak = 0;
    int longestStreak = 0;
    int tempStreak = 0;
    DateTime? lastDate;

    for (final log in sortedLogs) {
      if (log.minutesRead == 0) continue;

      if (lastDate == null) {
        tempStreak = 1;
      } else {
        final daysDiff = log.date.difference(lastDate).inDays;
        if (daysDiff == 1) {
          tempStreak++;
        } else {
          if (tempStreak > longestStreak) longestStreak = tempStreak;
          tempStreak = 1;
        }
      }

      lastDate = log.date;
    }

    // Check final streak
    if (tempStreak > longestStreak) longestStreak = tempStreak;

    // Current streak is the streak ending on the most recent date
    if (lastDate != null) {
      final daysSinceLastReading = DateTime.now().difference(lastDate).inDays;
      if (daysSinceLastReading <= 1) {
        currentStreak = tempStreak;
      }
    }

    return {'current': currentStreak, 'longest': longestStreak};
  }

  List<Map<String, dynamic>> _calculateWeeklyData(
    List<ReadingLogModel> sortedLogs,
    DateTime startDate,
    DateTime endDate,
  ) {
    // Group logs by week
    final weeklyMinutes = <String, int>{};

    for (final log in sortedLogs) {
      final weekStart = _getWeekStart(log.date);
      final weekLabel = DateFormat('MMM dd').format(weekStart);
      weeklyMinutes[weekLabel] =
          (weeklyMinutes[weekLabel] ?? 0) + log.minutesRead;
    }

    // Convert to list format for chart
    return weeklyMinutes.entries
        .map((e) => {'label': e.key, 'minutes': e.value})
        .toList();
  }

  DateTime _getWeekStart(DateTime date) {
    final weekday = date.weekday;
    return date.subtract(Duration(days: weekday - 1));
  }

  List<String> _generateRecommendations(
    Map<String, dynamic> metrics,
    StudentModel student,
  ) {
    final recommendations = <String>[];
    final avgMinutes = metrics['avgMinutesPerDay'] as double;
    final currentStreak = metrics['currentStreak'] as int;
    final targetMetPct = metrics['targetMetPercentage'] as double;
    final readingDays = metrics['readingDays'] as int;

    // Celebrate successes
    if (currentStreak >= 7) {
      recommendations.add(
        '🎉 Excellent work! ${student.firstName} has maintained a $currentStreak-day reading streak. Keep up the amazing consistency!',
      );
    }

    if (targetMetPct >= 80) {
      recommendations.add(
        '⭐ Outstanding performance! Meeting reading targets ${targetMetPct.toStringAsFixed(0)}% of the time shows strong commitment.',
      );
    }

    // Provide guidance for improvement
    if (avgMinutes < 15) {
      recommendations.add(
        '📖 Try to increase daily reading time. Currently averaging ${avgMinutes.toStringAsFixed(1)} minutes. Aim for at least 20 minutes daily for best results.',
      );
    }

    if (currentStreak == 0 && readingDays > 0) {
      recommendations.add(
        '🎯 Focus on building consistency. Try setting a daily reminder to read at the same time each day.',
      );
    }

    if (targetMetPct < 50) {
      recommendations.add(
        '💡 Consider adjusting reading goals if targets are too challenging, or set aside dedicated reading time each day.',
      );
    }

    // General encouragement
    if (readingDays > 0) {
      recommendations.add(
        '📚 Continue exploring different books and genres to maintain interest and engagement.',
      );
    } else {
      recommendations.add(
        '🚀 Let\'s get started! Begin with just 10 minutes of reading daily and gradually build the habit.',
      );
    }

    // Always include next step
    if (currentStreak < 7) {
      recommendations.add(
        '🎯 Next milestone: Build a 7-day reading streak to unlock the Week Warrior achievement!',
      );
    } else if (currentStreak < 30) {
      recommendations.add(
        '🎯 Next milestone: Reach a 30-day streak to earn the Monthly Master badge!',
      );
    }

    return recommendations;
  }

  Future<File> _savePdfToFile(pw.Document pdf, String filename) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$filename');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  /// Preview a PDF document (for testing/development)
  Future<void> previewPdf(pw.Document pdf) async {
    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
    );
  }

  /// Share a PDF file
  Future<void> sharePdf(File pdfFile) async {
    await Printing.sharePdf(
      bytes: await pdfFile.readAsBytes(),
      filename: pdfFile.path.split('/').last,
    );
  }

  /// Print a PDF file
  Future<void> printPdf(File pdfFile) async {
    await Printing.layoutPdf(
      onLayout: (format) async => pdfFile.readAsBytes(),
    );
  }
}
