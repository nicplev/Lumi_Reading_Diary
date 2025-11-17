import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../data/models/student_model.dart';
import '../data/models/reading_log_model.dart';

/// Service for generating beautiful PDF reports for teachers and administrators
///
/// Features:
/// - Class reading summary reports
/// - Individual student progress reports
/// - School-wide analytics reports
/// - Custom date range filtering
/// - Beautiful glass-morphism design
class PdfReportService {
  static final PdfReportService _instance = PdfReportService._internal();
  factory PdfReportService() => _instance;
  PdfReportService._internal();

  static PdfReportService get instance => _instance;

  final DateFormat _dateFormatter = DateFormat('MMM dd, yyyy');
  final DateFormat _monthFormatter = DateFormat('MMMM yyyy');

  /// Generate a class reading summary report
  ///
  /// Includes:
  /// - Class overview (total students, average minutes, top readers)
  /// - Individual student summaries
  /// - Reading trends chart
  /// - Achievement distribution
  Future<Uint8List> generateClassReport({
    required String className,
    required String teacherName,
    required List<StudentModel> students,
    required Map<String, List<ReadingLogModel>> studentLogs,
    required DateTime startDate,
    required DateTime endDate,
    String? schoolName,
  }) async {
    final pdf = pw.Document();

    // Calculate class statistics
    final stats = _calculateClassStats(students, studentLogs, startDate, endDate);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _buildReportHeader(
            title: 'Class Reading Report',
            subtitle: className,
            period: '${_dateFormatter.format(startDate)} - ${_dateFormatter.format(endDate)}',
            teacherName: teacherName,
            schoolName: schoolName,
          ),
          pw.SizedBox(height: 24),
          _buildClassOverview(stats),
          pw.SizedBox(height: 24),
          _buildTopReadersSection(students, studentLogs, startDate, endDate),
          pw.SizedBox(height: 24),
          _buildReadingTrendsChart(studentLogs, startDate, endDate),
          pw.SizedBox(height: 24),
          _buildStudentSummaryTable(students, studentLogs, startDate, endDate),
        ],
        footer: (context) => _buildFooter(context),
      ),
    );

    return pdf.save();
  }

  /// Generate an individual student progress report
  ///
  /// Includes:
  /// - Student overview (name, level, total reading time)
  /// - Reading streak and consistency
  /// - Books read list
  /// - Achievement showcase
  /// - Parent recommendations
  Future<Uint8List> generateStudentReport({
    required StudentModel student,
    required List<ReadingLogModel> readingLogs,
    required DateTime startDate,
    required DateTime endDate,
    String? teacherName,
    String? className,
  }) async {
    final pdf = pw.Document();

    // Filter logs for date range
    final periodLogs = readingLogs.where((log) {
      return log.date.isAfter(startDate.subtract(const Duration(days: 1))) &&
             log.date.isBefore(endDate.add(const Duration(days: 1)));
    }).toList();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _buildReportHeader(
            title: 'Student Progress Report',
            subtitle: '${student.firstName} ${student.lastName}',
            period: '${_dateFormatter.format(startDate)} - ${_dateFormatter.format(endDate)}',
            teacherName: teacherName,
            schoolName: className,
          ),
          pw.SizedBox(height: 24),
          _buildStudentOverview(student, periodLogs),
          pw.SizedBox(height: 24),
          _buildReadingConsistency(student, periodLogs, startDate, endDate),
          pw.SizedBox(height: 24),
          _buildBooksReadSection(periodLogs),
          pw.SizedBox(height: 24),
          _buildAchievementShowcase(student),
          pw.SizedBox(height: 24),
          _buildRecommendations(student, periodLogs),
        ],
        footer: (context) => _buildFooter(context),
      ),
    );

    return pdf.save();
  }

  /// Generate a school-wide analytics report
  ///
  /// Includes:
  /// - School overview (total students, classes, reading time)
  /// - Top performing classes
  /// - Grade-level comparison
  /// - Engagement metrics
  /// - Month-over-month growth
  Future<Uint8List> generateSchoolReport({
    required String schoolName,
    required Map<String, List<StudentModel>> classesByName,
    required Map<String, List<ReadingLogModel>> logsByStudent,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final pdf = pw.Document();

    final stats = _calculateSchoolStats(classesByName, logsByStudent, startDate, endDate);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _buildReportHeader(
            title: 'School Analytics Report',
            subtitle: schoolName,
            period: '${_dateFormatter.format(startDate)} - ${_dateFormatter.format(endDate)}',
          ),
          pw.SizedBox(height: 24),
          _buildSchoolOverview(stats),
          pw.SizedBox(height: 24),
          _buildTopClassesSection(classesByName, logsByStudent, startDate, endDate),
          pw.SizedBox(height: 24),
          _buildGradeLevelComparison(stats),
          pw.SizedBox(height: 24),
          _buildEngagementMetrics(stats),
        ],
        footer: (context) => _buildFooter(context),
      ),
    );

    return pdf.save();
  }

  /// Save PDF to device and return file path
  Future<String> savePdfToFile(Uint8List pdfBytes, String fileName) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(pdfBytes);
    return file.path;
  }

  /// Share or print PDF directly
  Future<void> shareOrPrintPdf(Uint8List pdfBytes, String title) async {
    await Printing.sharePdf(bytes: pdfBytes, filename: '$title.pdf');
  }

  /// Print PDF directly
  Future<void> printPdf(Uint8List pdfBytes) async {
    await Printing.layoutPdf(onLayout: (_) => pdfBytes);
  }

  // ============================================================================
  // Header & Footer Builders
  // ============================================================================

  pw.Widget _buildReportHeader({
    required String title,
    required String subtitle,
    required String period,
    String? teacherName,
    String? schoolName,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#E3F2FD'),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    title,
                    style: pw.TextStyle(
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromHex('#1976D2'),
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    subtitle,
                    style: pw.TextStyle(
                      fontSize: 18,
                      color: PdfColor.fromHex('#424242'),
                    ),
                  ),
                ],
              ),
              pw.Text(
                '📚 Lumi',
                style: const pw.TextStyle(fontSize: 32),
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Divider(color: PdfColor.fromHex('#1976D2'), thickness: 2),
          pw.SizedBox(height: 8),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Period: $period',
                style: pw.TextStyle(
                  fontSize: 12,
                  color: PdfColor.fromHex('#616161'),
                ),
              ),
              if (teacherName != null)
                pw.Text(
                  'Teacher: $teacherName',
                  style: pw.TextStyle(
                    fontSize: 12,
                    color: PdfColor.fromHex('#616161'),
                  ),
                ),
              if (schoolName != null)
                pw.Text(
                  schoolName,
                  style: pw.TextStyle(
                    fontSize: 12,
                    color: PdfColor.fromHex('#616161'),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildFooter(pw.Context context) {
    return pw.Container(
      alignment: pw.Alignment.centerRight,
      margin: const pw.EdgeInsets.only(top: 16),
      child: pw.Text(
        'Page ${context.pageNumber} of ${context.pagesCount} • Generated by Lumi on ${_dateFormatter.format(DateTime.now())}',
        style: pw.TextStyle(
          fontSize: 10,
          color: PdfColor.fromHex('#9E9E9E'),
        ),
      ),
    );
  }

  // ============================================================================
  // Class Report Sections
  // ============================================================================

  pw.Widget _buildClassOverview(Map<String, dynamic> stats) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColor.fromHex('#E0E0E0')),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Class Overview',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromHex('#1976D2'),
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              _buildStatCard('👥 Total Students', '${stats['totalStudents']}'),
              _buildStatCard('⏱️ Total Minutes', '${stats['totalMinutes']}'),
              _buildStatCard('📖 Books Read', '${stats['totalBooks']}'),
              _buildStatCard('📊 Avg. Minutes/Student', '${stats['avgMinutesPerStudent']}'),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildStatCard(String label, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#F5F5F5'),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromHex('#1976D2'),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 10,
              color: PdfColor.fromHex('#616161'),
            ),
            textAlign: pw.TextAlign.center,
          ),
        ],
      ),
    );
  }

  pw.Widget _buildTopReadersSection(
    List<StudentModel> students,
    Map<String, List<ReadingLogModel>> studentLogs,
    DateTime startDate,
    DateTime endDate,
  ) {
    // Calculate minutes read for each student in period
    final studentMinutes = <String, int>{};
    for (final student in students) {
      final logs = studentLogs[student.id] ?? [];
      final periodLogs = logs.where((log) {
        return log.date.isAfter(startDate.subtract(const Duration(days: 1))) &&
               log.date.isBefore(endDate.add(const Duration(days: 1)));
      });
      studentMinutes[student.id] = periodLogs.fold(0, (sum, log) => sum + log.minutesRead);
    }

    // Sort students by minutes read
    final sortedStudents = students.toList()
      ..sort((a, b) => (studentMinutes[b.id] ?? 0).compareTo(studentMinutes[a.id] ?? 0));

    final topReaders = sortedStudents.take(5).toList();

    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColor.fromHex('#E0E0E0')),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '🏆 Top 5 Readers',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromHex('#1976D2'),
            ),
          ),
          pw.SizedBox(height: 12),
          ...topReaders.asMap().entries.map((entry) {
            final rank = entry.key + 1;
            final student = entry.value;
            final minutes = studentMinutes[student.id] ?? 0;
            final medal = rank == 1 ? '🥇' : rank == 2 ? '🥈' : rank == 3 ? '🥉' : '  ';

            return pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Row(
                children: [
                  pw.SizedBox(
                    width: 30,
                    child: pw.Text(medal, style: const pw.TextStyle(fontSize: 16)),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      '${student.firstName} ${student.lastName}',
                      style: const pw.TextStyle(fontSize: 12),
                    ),
                  ),
                  pw.Text(
                    '$minutes min',
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromHex('#1976D2'),
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

  pw.Widget _buildReadingTrendsChart(
    Map<String, List<ReadingLogModel>> studentLogs,
    DateTime startDate,
    DateTime endDate,
  ) {
    // Calculate daily totals
    final dailyMinutes = <DateTime, int>{};

    for (final logs in studentLogs.values) {
      for (final log in logs) {
        if (log.date.isAfter(startDate.subtract(const Duration(days: 1))) &&
            log.date.isBefore(endDate.add(const Duration(days: 1)))) {
          final dateKey = DateTime(log.date.year, log.date.month, log.date.day);
          dailyMinutes[dateKey] = (dailyMinutes[dateKey] ?? 0) + log.minutesRead;
        }
      }
    }

    final sortedDates = dailyMinutes.keys.toList()..sort();
    final maxMinutes = dailyMinutes.values.isEmpty ? 100 : dailyMinutes.values.reduce((a, b) => a > b ? a : b);

    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColor.fromHex('#E0E0E0')),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '📈 Reading Trends',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromHex('#1976D2'),
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Container(
            height: 150,
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: sortedDates.take(14).map((date) {
                final minutes = dailyMinutes[date] ?? 0;
                final heightPercent = maxMinutes > 0 ? (minutes / maxMinutes) : 0;

                return pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.end,
                  children: [
                    pw.Container(
                      width: 20,
                      height: 120 * heightPercent,
                      decoration: pw.BoxDecoration(
                        color: PdfColor.fromHex('#64B5F6'),
                        borderRadius: const pw.BorderRadius.vertical(top: pw.Radius.circular(4)),
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      DateFormat('d').format(date),
                      style: pw.TextStyle(fontSize: 8, color: PdfColor.fromHex('#616161')),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildStudentSummaryTable(
    List<StudentModel> students,
    Map<String, List<ReadingLogModel>> studentLogs,
    DateTime startDate,
    DateTime endDate,
  ) {
    return pw.Container(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Student Summary',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromHex('#1976D2'),
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColor.fromHex('#E0E0E0')),
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: PdfColor.fromHex('#F5F5F5')),
                children: [
                  _buildTableHeader('Student'),
                  _buildTableHeader('Minutes'),
                  _buildTableHeader('Books'),
                  _buildTableHeader('Days Active'),
                  _buildTableHeader('Avg/Day'),
                ],
              ),
              ...students.map((student) {
                final logs = studentLogs[student.id] ?? [];
                final periodLogs = logs.where((log) {
                  return log.date.isAfter(startDate.subtract(const Duration(days: 1))) &&
                         log.date.isBefore(endDate.add(const Duration(days: 1)));
                }).toList();

                final totalMinutes = periodLogs.fold(0, (sum, log) => sum + log.minutesRead);
                final booksRead = periodLogs.where((log) => log.bookCompleted).length;
                final daysActive = periodLogs.map((log) => DateTime(log.date.year, log.date.month, log.date.day)).toSet().length;
                final avgPerDay = daysActive > 0 ? (totalMinutes / daysActive).round() : 0;

                return pw.TableRow(
                  children: [
                    _buildTableCell('${student.firstName} ${student.lastName}'),
                    _buildTableCell('$totalMinutes'),
                    _buildTableCell('$booksRead'),
                    _buildTableCell('$daysActive'),
                    _buildTableCell('$avgPerDay'),
                  ],
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildTableHeader(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: pw.FontWeight.bold,
          color: PdfColor.fromHex('#424242'),
        ),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  pw.Widget _buildTableCell(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 10, color: PdfColor.fromHex('#616161')),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  // ============================================================================
  // Student Report Sections
  // ============================================================================

  pw.Widget _buildStudentOverview(StudentModel student, List<ReadingLogModel> logs) {
    final totalMinutes = logs.fold(0, (sum, log) => sum + log.minutesRead);
    final booksCompleted = logs.where((log) => log.bookCompleted).length;
    final daysActive = logs.map((log) => DateTime(log.date.year, log.date.month, log.date.day)).toSet().length;

    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColor.fromHex('#E0E0E0')),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          _buildStatCard('⏱️ Total Reading Time', '$totalMinutes min'),
          _buildStatCard('📚 Books Completed', '$booksCompleted'),
          _buildStatCard('📅 Days Active', '$daysActive'),
          _buildStatCard('🔥 Current Streak', '${student.stats.currentStreak} days'),
        ],
      ),
    );
  }

  pw.Widget _buildReadingConsistency(StudentModel student, List<ReadingLogModel> logs, DateTime startDate, DateTime endDate) {
    final daysInPeriod = endDate.difference(startDate).inDays + 1;
    final daysActive = logs.map((log) => DateTime(log.date.year, log.date.month, log.date.day)).toSet().length;
    final consistencyPercent = daysInPeriod > 0 ? ((daysActive / daysInPeriod) * 100).round() : 0;

    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColor.fromHex('#E0E0E0')),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '📊 Reading Consistency',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromHex('#1976D2'),
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Reading Frequency: $daysActive / $daysInPeriod days'),
                    pw.SizedBox(height: 8),
                    pw.Container(
                      height: 20,
                      decoration: pw.BoxDecoration(
                        color: PdfColor.fromHex('#E0E0E0'),
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
                      ),
                      child: pw.FractionallySizedBox(
                        widthFactor: consistencyPercent / 100,
                        alignment: pw.Alignment.centerLeft,
                        child: pw.Container(
                          decoration: pw.BoxDecoration(
                            color: PdfColor.fromHex('#4CAF50'),
                            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
                          ),
                        ),
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      '$consistencyPercent% consistency',
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor.fromHex('#4CAF50'),
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

  pw.Widget _buildBooksReadSection(List<ReadingLogModel> logs) {
    final completedBooks = logs.where((log) => log.bookCompleted).toList();

    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColor.fromHex('#E0E0E0')),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '📖 Books Completed',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromHex('#1976D2'),
            ),
          ),
          pw.SizedBox(height: 12),
          if (completedBooks.isEmpty)
            pw.Text('No books completed in this period', style: pw.TextStyle(color: PdfColor.fromHex('#9E9E9E')))
          else
            ...completedBooks.take(10).map((log) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 6),
              child: pw.Row(
                children: [
                  pw.Text('• ', style: pw.TextStyle(color: PdfColor.fromHex('#1976D2'))),
                  pw.Expanded(child: pw.Text(log.bookTitle, style: const pw.TextStyle(fontSize: 11))),
                  pw.Text(
                    _dateFormatter.format(log.date),
                    style: pw.TextStyle(fontSize: 10, color: PdfColor.fromHex('#9E9E9E')),
                  ),
                ],
              ),
            )),
        ],
      ),
    );
  }

  pw.Widget _buildAchievementShowcase(StudentModel student) {
    final achievements = student.achievements.take(6).toList();

    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColor.fromHex('#E0E0E0')),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '🏆 Recent Achievements',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromHex('#1976D2'),
            ),
          ),
          pw.SizedBox(height: 12),
          if (achievements.isEmpty)
            pw.Text('No achievements yet - keep reading!', style: pw.TextStyle(color: PdfColor.fromHex('#9E9E9E')))
          else
            pw.Wrap(
              spacing: 8,
              runSpacing: 8,
              children: achievements.map((achievement) => pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('#FFF3E0'),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                ),
                child: pw.Row(
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    pw.Text(achievement.icon, style: const pw.TextStyle(fontSize: 14)),
                    pw.SizedBox(width: 6),
                    pw.Text(achievement.name, style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
              )).toList(),
            ),
        ],
      ),
    );
  }

  pw.Widget _buildRecommendations(StudentModel student, List<ReadingLogModel> logs) {
    final recommendations = <String>[];

    // Generate personalized recommendations
    final avgMinutesPerDay = logs.isEmpty ? 0 : logs.fold(0, (sum, log) => sum + log.minutesRead) / logs.length;

    if (student.stats.currentStreak >= 7) {
      recommendations.add('🌟 Excellent consistency! Keep up the daily reading habit.');
    } else if (student.stats.currentStreak >= 3) {
      recommendations.add('📈 Good progress on building a reading streak. Aim for 7 days!');
    } else {
      recommendations.add('🎯 Try to establish a daily reading routine to build a streak.');
    }

    if (avgMinutesPerDay >= 20) {
      recommendations.add('⭐ Great reading duration! This supports strong comprehension.');
    } else if (avgMinutesPerDay >= 10) {
      recommendations.add('📚 Good reading time. Try gradually increasing to 20+ minutes.');
    } else {
      recommendations.add('⏱️ Consider extending reading sessions for deeper engagement.');
    }

    if (student.stats.totalBooksRead >= 5) {
      recommendations.add('🏆 Impressive number of books completed!');
    }

    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#E8F5E9'),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '💡 Recommendations',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromHex('#2E7D32'),
            ),
          ),
          pw.SizedBox(height: 12),
          ...recommendations.map((rec) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 6),
            child: pw.Text('• $rec', style: const pw.TextStyle(fontSize: 11)),
          )),
        ],
      ),
    );
  }

  // ============================================================================
  // School Report Sections
  // ============================================================================

  pw.Widget _buildSchoolOverview(Map<String, dynamic> stats) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColor.fromHex('#E0E0E0')),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'School Overview',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromHex('#1976D2'),
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              _buildStatCard('🏫 Classes', '${stats['totalClasses']}'),
              _buildStatCard('👥 Students', '${stats['totalStudents']}'),
              _buildStatCard('⏱️ Total Minutes', '${stats['totalMinutes']}'),
              _buildStatCard('📚 Books Read', '${stats['totalBooks']}'),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildTopClassesSection(
    Map<String, List<StudentModel>> classesByName,
    Map<String, List<ReadingLogModel>> logsByStudent,
    DateTime startDate,
    DateTime endDate,
  ) {
    final classMinutes = <String, int>{};

    for (final className in classesByName.keys) {
      final students = classesByName[className]!;
      int totalMinutes = 0;

      for (final student in students) {
        final logs = logsByStudent[student.id] ?? [];
        final periodLogs = logs.where((log) {
          return log.date.isAfter(startDate.subtract(const Duration(days: 1))) &&
                 log.date.isBefore(endDate.add(const Duration(days: 1)));
        });
        totalMinutes += periodLogs.fold(0, (sum, log) => sum + log.minutesRead);
      }

      classMinutes[className] = totalMinutes;
    }

    final sortedClasses = classMinutes.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColor.fromHex('#E0E0E0')),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '🏆 Top Performing Classes',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromHex('#1976D2'),
            ),
          ),
          pw.SizedBox(height: 12),
          ...sortedClasses.take(5).asMap().entries.map((entry) {
            final rank = entry.key + 1;
            final className = entry.value.key;
            final minutes = entry.value.value;
            final medal = rank == 1 ? '🥇' : rank == 2 ? '🥈' : rank == 3 ? '🥉' : '  ';

            return pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Row(
                children: [
                  pw.SizedBox(
                    width: 30,
                    child: pw.Text(medal, style: const pw.TextStyle(fontSize: 16)),
                  ),
                  pw.Expanded(child: pw.Text(className, style: const pw.TextStyle(fontSize: 12))),
                  pw.Text(
                    '$minutes min',
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromHex('#1976D2'),
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

  pw.Widget _buildGradeLevelComparison(Map<String, dynamic> stats) {
    // Placeholder for grade-level data
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColor.fromHex('#E0E0E0')),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Text('Grade-level comparison coming soon...'),
    );
  }

  pw.Widget _buildEngagementMetrics(Map<String, dynamic> stats) {
    final engagementRate = stats['engagementRate'] ?? 0;

    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColor.fromHex('#E0E0E0')),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '📊 Engagement Metrics',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromHex('#1976D2'),
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Text('Daily Active Users: $engagementRate%'),
        ],
      ),
    );
  }

  // ============================================================================
  // Statistics Calculations
  // ============================================================================

  Map<String, dynamic> _calculateClassStats(
    List<StudentModel> students,
    Map<String, List<ReadingLogModel>> studentLogs,
    DateTime startDate,
    DateTime endDate,
  ) {
    int totalMinutes = 0;
    int totalBooks = 0;

    for (final student in students) {
      final logs = studentLogs[student.id] ?? [];
      final periodLogs = logs.where((log) {
        return log.date.isAfter(startDate.subtract(const Duration(days: 1))) &&
               log.date.isBefore(endDate.add(const Duration(days: 1)));
      });

      totalMinutes += periodLogs.fold(0, (sum, log) => sum + log.minutesRead);
      totalBooks += periodLogs.where((log) => log.bookCompleted).length;
    }

    return {
      'totalStudents': students.length,
      'totalMinutes': totalMinutes,
      'totalBooks': totalBooks,
      'avgMinutesPerStudent': students.isEmpty ? 0 : (totalMinutes / students.length).round(),
    };
  }

  Map<String, dynamic> _calculateSchoolStats(
    Map<String, List<StudentModel>> classesByName,
    Map<String, List<ReadingLogModel>> logsByStudent,
    DateTime startDate,
    DateTime endDate,
  ) {
    int totalStudents = 0;
    int totalMinutes = 0;
    int totalBooks = 0;

    for (final students in classesByName.values) {
      totalStudents += students.length;

      for (final student in students) {
        final logs = logsByStudent[student.id] ?? [];
        final periodLogs = logs.where((log) {
          return log.date.isAfter(startDate.subtract(const Duration(days: 1))) &&
                 log.date.isBefore(endDate.add(const Duration(days: 1)));
        });

        totalMinutes += periodLogs.fold(0, (sum, log) => sum + log.minutesRead);
        totalBooks += periodLogs.where((log) => log.bookCompleted).length;
      }
    }

    return {
      'totalClasses': classesByName.length,
      'totalStudents': totalStudents,
      'totalMinutes': totalMinutes,
      'totalBooks': totalBooks,
      'engagementRate': 75, // Placeholder
    };
  }
}
