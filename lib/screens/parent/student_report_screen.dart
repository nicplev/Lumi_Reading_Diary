import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/pdf_report_service.dart';
import '../../services/firebase_service.dart';
import '../../data/models/student_model.dart';
import '../../data/models/reading_log_model.dart';
import '../../core/widgets/glass/glass_container.dart';
import '../../core/widgets/glass/glass_button.dart';

/// Parent/Teacher screen for generating individual student progress reports
///
/// Features:
/// - Date range selection
/// - Student selection (for teachers with multiple students)
/// - Preview report stats
/// - Generate, save, share, or print PDF
/// - Personalized recommendations
class StudentReportScreen extends StatefulWidget {
  final String studentId;
  final String schoolId;
  final String? parentId; // If accessed by parent

  const StudentReportScreen({
    super.key,
    required this.studentId,
    required this.schoolId,
    this.parentId,
  });

  @override
  State<StudentReportScreen> createState() => _StudentReportScreenState();
}

class _StudentReportScreenState extends State<StudentReportScreen> {
  final _pdfService = PdfReportService.instance;
  final _firebaseService = FirebaseService.instance;

  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();

  bool _isLoading = false;
  bool _isGenerating = false;

  StudentModel? _student;
  List<ReadingLogModel> _allLogs = [];
  Map<String, dynamic>? _previewStats;

  @override
  void initState() {
    super.initState();
    _loadStudentData();
  }

  Future<void> _loadStudentData() async {
    setState(() => _isLoading = true);

    try {
      // Load student
      final studentDoc = await _firebaseService.firestore
          .collection('schools')
          .doc(widget.schoolId)
          .collection('students')
          .doc(widget.studentId)
          .get();

      if (!studentDoc.exists) {
        throw Exception('Student not found');
      }

      final student = StudentModel.fromFirestore(studentDoc);

      // Load all reading logs
      final logsSnapshot = await _firebaseService.firestore
          .collection('schools')
          .doc(widget.schoolId)
          .collection('readingLogs')
          .where('studentId', isEqualTo: widget.studentId)
          .orderBy('date', descending: true)
          .get();

      final logs = logsSnapshot.docs
          .map((doc) => ReadingLogModel.fromFirestore(doc))
          .toList();

      setState(() {
        _student = student;
        _allLogs = logs;
      });

      _calculatePreviewStats();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading student data: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _calculatePreviewStats() {
    if (_student == null) return;

    final periodLogs = _allLogs.where((log) {
      return log.date.isAfter(_startDate.subtract(const Duration(days: 1))) &&
             log.date.isBefore(_endDate.add(const Duration(days: 1)));
    }).toList();

    final totalMinutes = periodLogs.fold(0, (sum, log) => sum + log.minutesRead);
    final booksCompleted = periodLogs.where((log) => log.bookCompleted).length;
    final daysActive = periodLogs
        .map((log) => DateTime(log.date.year, log.date.month, log.date.day))
        .toSet()
        .length;
    final avgMinutesPerDay = daysActive > 0 ? (totalMinutes / daysActive).round() : 0;

    setState(() {
      _previewStats = {
        'totalMinutes': totalMinutes,
        'booksCompleted': booksCompleted,
        'daysActive': daysActive,
        'avgMinutesPerDay': avgMinutesPerDay,
        'currentStreak': _student!.stats.currentStreak,
      };
    });
  }

  Future<void> _generateAndShareReport() async {
    if (_student == null) return;

    setState(() => _isGenerating = true);

    try {
      // Filter logs for date range
      final periodLogs = _allLogs.where((log) {
        return log.date.isAfter(_startDate.subtract(const Duration(days: 1))) &&
               log.date.isBefore(_endDate.add(const Duration(days: 1)));
      }).toList();

      // Get class name if available
      String? className;
      if (_student!.classId != null) {
        final classDoc = await _firebaseService.firestore
            .collection('schools')
            .doc(widget.schoolId)
            .collection('classes')
            .doc(_student!.classId)
            .get();

        className = classDoc.data()?['name'] as String?;
      }

      // Get teacher name if available
      String? teacherName;
      if (_student!.classId != null) {
        final classDoc = await _firebaseService.firestore
            .collection('schools')
            .doc(widget.schoolId)
            .collection('classes')
            .doc(_student!.classId)
            .get();

        final teacherId = classDoc.data()?['teacherId'] as String?;
        if (teacherId != null) {
          final teacherDoc = await _firebaseService.firestore
              .collection('schools')
              .doc(widget.schoolId)
              .collection('teachers')
              .doc(teacherId)
              .get();

          teacherName = teacherDoc.data()?['name'] as String?;
        }
      }

      // Generate PDF
      final pdfBytes = await _pdfService.generateStudentReport(
        student: _student!,
        readingLogs: periodLogs,
        startDate: _startDate,
        endDate: _endDate,
        teacherName: teacherName,
        className: className,
      );

      // Share PDF
      await _pdfService.shareOrPrintPdf(
        pdfBytes,
        '${_student!.firstName}_${_student!.lastName}_Progress_${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📄 Student report generated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating report: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  Future<void> _generateAndPrintReport() async {
    if (_student == null) return;

    setState(() => _isGenerating = true);

    try {
      // Filter logs for date range
      final periodLogs = _allLogs.where((log) {
        return log.date.isAfter(_startDate.subtract(const Duration(days: 1))) &&
               log.date.isBefore(_endDate.add(const Duration(days: 1)));
      }).toList();

      // Get class name if available
      String? className;
      if (_student!.classId != null) {
        final classDoc = await _firebaseService.firestore
            .collection('schools')
            .doc(widget.schoolId)
            .collection('classes')
            .doc(_student!.classId)
            .get();

        className = classDoc.data()?['name'] as String?;
      }

      // Get teacher name if available
      String? teacherName;
      if (_student!.classId != null) {
        final classDoc = await _firebaseService.firestore
            .collection('schools')
            .doc(widget.schoolId)
            .collection('classes')
            .doc(_student!.classId)
            .get();

        final teacherId = classDoc.data()?['teacherId'] as String?;
        if (teacherId != null) {
          final teacherDoc = await _firebaseService.firestore
              .collection('schools')
              .doc(widget.schoolId)
              .collection('teachers')
              .doc(teacherId)
              .get();

          teacherName = teacherDoc.data()?['name'] as String?;
        }
      }

      // Generate PDF
      final pdfBytes = await _pdfService.generateStudentReport(
        student: _student!,
        readingLogs: periodLogs,
        startDate: _startDate,
        endDate: _endDate,
        teacherName: teacherName,
        className: className,
      );

      // Print PDF
      await _pdfService.printPdf(pdfBytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🖨️ Printing student report...'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error printing report: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF1976D2),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _calculatePreviewStats();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Student Progress Report'),
        backgroundColor: const Color(0xFF1976D2),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading && _student == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Student Header
                  if (_student != null) ...[
                    GlassContainer(
                      child: Row(
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: const Color(0xFF1976D2).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Center(
                              child: Text(
                                '${_student!.firstName[0]}${_student!.lastName[0]}',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1976D2),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${_student!.firstName} ${_student!.lastName}',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Level: ${_student!.readingLevel}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFF616161),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Date Range Selection
                  const Text(
                    '📊 Generate Progress Report',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1976D2),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Create a comprehensive progress report with insights and recommendations',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF616161),
                    ),
                  ),
                  const SizedBox(height: 24),

                  GlassContainer(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '📅 Date Range',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        InkWell(
                          onTap: _selectDateRange,
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFE0E0E0)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${DateFormat('MMM dd, yyyy').format(_startDate)} - ${DateFormat('MMM dd, yyyy').format(_endDate)}',
                                  style: const TextStyle(fontSize: 14),
                                ),
                                const Icon(Icons.calendar_today, size: 20),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _buildQuickDateButton('Last Week', 7),
                            const SizedBox(width: 8),
                            _buildQuickDateButton('Last Month', 30),
                            const SizedBox(width: 8),
                            _buildQuickDateButton('This Term', 90),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Preview Stats
                  if (_previewStats != null) ...[
                    const Text(
                      '📈 Report Preview',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1976D2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    GlassContainer(
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _buildPreviewCard(
                                  '⏱️',
                                  'Total Minutes',
                                  '${_previewStats!['totalMinutes']}',
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildPreviewCard(
                                  '📖',
                                  'Books Completed',
                                  '${_previewStats!['booksCompleted']}',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildPreviewCard(
                                  '📅',
                                  'Days Active',
                                  '${_previewStats!['daysActive']}',
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildPreviewCard(
                                  '🔥',
                                  'Current Streak',
                                  '${_previewStats!['currentStreak']} days',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Report includes
                    GlassContainer(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '📋 Report Includes:',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildIncludesItem('📊 Reading statistics and trends'),
                          _buildIncludesItem('📚 List of books completed'),
                          _buildIncludesItem('🏆 Achievements and badges earned'),
                          _buildIncludesItem('📈 Consistency and streak analysis'),
                          _buildIncludesItem('💡 Personalized recommendations'),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Action Buttons
                  if (_student != null) ...[
                    GlassButton(
                      onPressed: _isGenerating ? null : _generateAndShareReport,
                      child: _isGenerating
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(Colors.white),
                              ),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.share, color: Colors.white),
                                SizedBox(width: 8),
                                Text(
                                  'Generate & Share Report',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _isGenerating ? null : _generateAndPrintReport,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 56),
                        side: const BorderSide(color: Color(0xFF1976D2)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.print, color: Color(0xFF1976D2)),
                          SizedBox(width: 8),
                          Text(
                            'Print Report',
                            style: TextStyle(
                              fontSize: 16,
                              color: Color(0xFF1976D2),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildQuickDateButton(String label, int days) {
    return Expanded(
      child: OutlinedButton(
        onPressed: () {
          setState(() {
            _endDate = DateTime.now();
            _startDate = _endDate.subtract(Duration(days: days));
          });
          _calculatePreviewStats();
        },
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 8),
          side: const BorderSide(color: Color(0xFF1976D2)),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF1976D2)),
        ),
      ),
    );
  }

  Widget _buildPreviewCard(String emoji, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1976D2),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF616161),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildIncludesItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
