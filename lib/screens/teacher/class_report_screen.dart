import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/pdf_report_service.dart';
import '../../services/firebase_service.dart';
import '../../data/models/student_model.dart';
import '../../data/models/reading_log_model.dart';
import '../../core/widgets/glass/glass_container.dart';
import '../../core/widgets/glass/glass_button.dart';

/// Teacher screen for generating beautiful PDF class reports
///
/// Features:
/// - Date range selection
/// - Class selection
/// - Preview report stats
/// - Generate, save, share, or print PDF
/// - Beautiful glass-morphism UI
class ClassReportScreen extends StatefulWidget {
  final String teacherId;
  final String schoolId;

  const ClassReportScreen({
    super.key,
    required this.teacherId,
    required this.schoolId,
  });

  @override
  State<ClassReportScreen> createState() => _ClassReportScreenState();
}

class _ClassReportScreenState extends State<ClassReportScreen> {
  final _pdfService = PdfReportService.instance;
  final _firebaseService = FirebaseService.instance;

  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  String? _selectedClassId;
  String? _selectedClassName;

  bool _isLoading = false;
  bool _isGenerating = false;

  List<Map<String, String>> _classes = [];
  Map<String, dynamic>? _previewStats;

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    setState(() => _isLoading = true);

    try {
      final snapshot = await _firebaseService.firestore
          .collection('schools')
          .doc(widget.schoolId)
          .collection('classes')
          .where('teacherId', isEqualTo: widget.teacherId)
          .get();

      setState(() {
        _classes = snapshot.docs.map((doc) {
          return {
            'id': doc.id,
            'name': doc.data()['name'] as String? ?? 'Unnamed Class',
          };
        }).toList();

        if (_classes.isNotEmpty) {
          _selectedClassId = _classes.first['id'];
          _selectedClassName = _classes.first['name'];
          _loadPreviewStats();
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading classes: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadPreviewStats() async {
    if (_selectedClassId == null) return;

    setState(() => _isLoading = true);

    try {
      // Load students
      final studentsSnapshot = await _firebaseService.firestore
          .collection('schools')
          .doc(widget.schoolId)
          .collection('students')
          .where('classId', isEqualTo: _selectedClassId)
          .get();

      final students = studentsSnapshot.docs
          .map((doc) => StudentModel.fromFirestore(doc))
          .toList();

      // Load reading logs for all students
      int totalMinutes = 0;
      int totalBooks = 0;
      int activeDays = 0;

      for (final student in students) {
        final logsSnapshot = await _firebaseService.firestore
            .collection('schools')
            .doc(widget.schoolId)
            .collection('readingLogs')
            .where('studentId', isEqualTo: student.id)
            .where('date', isGreaterThanOrEqualTo: _startDate)
            .where('date', isLessThanOrEqualTo: _endDate)
            .get();

        final logs = logsSnapshot.docs
            .map((doc) => ReadingLogModel.fromFirestore(doc))
            .toList();

        totalMinutes += logs.fold(0, (sum, log) => sum + log.minutesRead);
        totalBooks += logs.where((log) => log.bookCompleted).length;

        final studentDays = logs
            .map((log) => DateTime(log.date.year, log.date.month, log.date.day))
            .toSet()
            .length;
        activeDays += studentDays;
      }

      setState(() {
        _previewStats = {
          'totalStudents': students.length,
          'totalMinutes': totalMinutes,
          'totalBooks': totalBooks,
          'avgMinutesPerStudent': students.isEmpty ? 0 : (totalMinutes / students.length).round(),
          'activeDays': activeDays,
        };
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading preview: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _generateAndShareReport() async {
    if (_selectedClassId == null || _selectedClassName == null) return;

    setState(() => _isGenerating = true);

    try {
      // Load students
      final studentsSnapshot = await _firebaseService.firestore
          .collection('schools')
          .doc(widget.schoolId)
          .collection('students')
          .where('classId', isEqualTo: _selectedClassId)
          .get();

      final students = studentsSnapshot.docs
          .map((doc) => StudentModel.fromFirestore(doc))
          .toList();

      // Load reading logs for all students
      final studentLogs = <String, List<ReadingLogModel>>{};

      for (final student in students) {
        final logsSnapshot = await _firebaseService.firestore
            .collection('schools')
            .doc(widget.schoolId)
            .collection('readingLogs')
            .where('studentId', isEqualTo: student.id)
            .where('date', isGreaterThanOrEqualTo: _startDate)
            .where('date', isLessThanOrEqualTo: _endDate)
            .get();

        studentLogs[student.id] = logsSnapshot.docs
            .map((doc) => ReadingLogModel.fromFirestore(doc))
            .toList();
      }

      // Get teacher name
      final teacherDoc = await _firebaseService.firestore
          .collection('schools')
          .doc(widget.schoolId)
          .collection('teachers')
          .doc(widget.teacherId)
          .get();

      final teacherName = teacherDoc.data()?['name'] as String? ?? 'Unknown Teacher';

      // Get school name
      final schoolDoc = await _firebaseService.firestore
          .collection('schools')
          .doc(widget.schoolId)
          .get();

      final schoolName = schoolDoc.data()?['name'] as String?;

      // Generate PDF
      final pdfBytes = await _pdfService.generateClassReport(
        className: _selectedClassName!,
        teacherName: teacherName,
        students: students,
        studentLogs: studentLogs,
        startDate: _startDate,
        endDate: _endDate,
        schoolName: schoolName,
      );

      // Share PDF
      await _pdfService.shareOrPrintPdf(
        pdfBytes,
        '${_selectedClassName}_Report_${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📄 Report generated successfully!'),
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
    if (_selectedClassId == null || _selectedClassName == null) return;

    setState(() => _isGenerating = true);

    try {
      // Load students
      final studentsSnapshot = await _firebaseService.firestore
          .collection('schools')
          .doc(widget.schoolId)
          .collection('students')
          .where('classId', isEqualTo: _selectedClassId)
          .get();

      final students = studentsSnapshot.docs
          .map((doc) => StudentModel.fromFirestore(doc))
          .toList();

      // Load reading logs for all students
      final studentLogs = <String, List<ReadingLogModel>>{};

      for (final student in students) {
        final logsSnapshot = await _firebaseService.firestore
            .collection('schools')
            .doc(widget.schoolId)
            .collection('readingLogs')
            .where('studentId', isEqualTo: student.id)
            .where('date', isGreaterThanOrEqualTo: _startDate)
            .where('date', isLessThanOrEqualTo: _endDate)
            .get();

        studentLogs[student.id] = logsSnapshot.docs
            .map((doc) => ReadingLogModel.fromFirestore(doc))
            .toList();
      }

      // Get teacher name
      final teacherDoc = await _firebaseService.firestore
          .collection('schools')
          .doc(widget.schoolId)
          .collection('teachers')
          .doc(widget.teacherId)
          .get();

      final teacherName = teacherDoc.data()?['name'] as String? ?? 'Unknown Teacher';

      // Get school name
      final schoolDoc = await _firebaseService.firestore
          .collection('schools')
          .doc(widget.schoolId)
          .get();

      final schoolName = schoolDoc.data()?['name'] as String?;

      // Generate PDF
      final pdfBytes = await _pdfService.generateClassReport(
        className: _selectedClassName!,
        teacherName: teacherName,
        students: students,
        studentLogs: studentLogs,
        startDate: _startDate,
        endDate: _endDate,
        schoolName: schoolName,
      );

      // Print PDF
      await _pdfService.printPdf(pdfBytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🖨️ Printing report...'),
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
      _loadPreviewStats();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Class Reports'),
        backgroundColor: const Color(0xFF1976D2),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading && _classes.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  const Text(
                    '📊 Generate Class Report',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1976D2),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Create beautiful PDF reports for your class reading progress',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF616161),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Class Selection
                  GlassContainer(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '📚 Select Class',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE0E0E0)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedClassId,
                              isExpanded: true,
                              items: _classes.map((classData) {
                                return DropdownMenuItem(
                                  value: classData['id'],
                                  child: Text(classData['name']!),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() {
                                  _selectedClassId = value;
                                  _selectedClassName = _classes
                                      .firstWhere((c) => c['id'] == value)['name'];
                                });
                                _loadPreviewStats();
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Date Range Selection
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
                            _buildQuickDateButton('Last 7 Days', 7),
                            const SizedBox(width: 8),
                            _buildQuickDateButton('Last 30 Days', 30),
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
                                  '👥',
                                  'Students',
                                  '${_previewStats!['totalStudents']}',
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildPreviewCard(
                                  '⏱️',
                                  'Total Minutes',
                                  '${_previewStats!['totalMinutes']}',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildPreviewCard(
                                  '📖',
                                  'Books Read',
                                  '${_previewStats!['totalBooks']}',
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildPreviewCard(
                                  '📊',
                                  'Avg/Student',
                                  '${_previewStats!['avgMinutesPerStudent']} min',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Action Buttons
                  if (_selectedClassId != null) ...[
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
          _loadPreviewStats();
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
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1976D2),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF616161),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
