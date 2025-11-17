import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/models/student_model.dart';
import '../data/models/reading_log_model.dart';
import 'firebase_service.dart';

/// Service for calculating and providing analytics data for school administrators
///
/// Features:
/// - Real-time school-wide metrics
/// - Class comparison analytics
/// - Reading trend analysis
/// - Engagement tracking
/// - Growth calculations
/// - Achievement distribution
class AnalyticsService {
  static final AnalyticsService _instance = AnalyticsService._internal();
  factory AnalyticsService() => _instance;
  AnalyticsService._internal();

  static AnalyticsService get instance => _instance;

  final _firebaseService = FirebaseService.instance;

  /// Get comprehensive school-wide analytics
  Future<SchoolAnalytics> getSchoolAnalytics({
    required String schoolId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      // Load all students
      final studentsSnapshot = await _firebaseService.firestore
          .collection('schools')
          .doc(schoolId)
          .collection('students')
          .get();

      final students = studentsSnapshot.docs
          .map((doc) => StudentModel.fromFirestore(doc))
          .toList();

      // Load all reading logs for the period
      final logsSnapshot = await _firebaseService.firestore
          .collection('schools')
          .doc(schoolId)
          .collection('readingLogs')
          .where('date', isGreaterThanOrEqualTo: startDate)
          .where('date', isLessThanOrEqualTo: endDate)
          .get();

      final logs = logsSnapshot.docs
          .map((doc) => ReadingLogModel.fromFirestore(doc))
          .toList();

      // Load all classes
      final classesSnapshot = await _firebaseService.firestore
          .collection('schools')
          .doc(schoolId)
          .collection('classes')
          .get();

      final classes = classesSnapshot.docs.map((doc) => {
        'id': doc.id,
        'name': doc.data()['name'] as String? ?? 'Unnamed Class',
        'teacherId': doc.data()['teacherId'] as String?,
      }).toList();

      return _calculateAnalytics(students, logs, classes, startDate, endDate);
    } catch (e) {
      throw Exception('Error loading analytics: $e');
    }
  }

  /// Get class-specific analytics
  Future<ClassAnalytics> getClassAnalytics({
    required String schoolId,
    required String classId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      // Load students in class
      final studentsSnapshot = await _firebaseService.firestore
          .collection('schools')
          .doc(schoolId)
          .collection('students')
          .where('classId', isEqualTo: classId)
          .get();

      final students = studentsSnapshot.docs
          .map((doc) => StudentModel.fromFirestore(doc))
          .toList();

      // Load reading logs for these students
      final studentIds = students.map((s) => s.id).toList();
      final List<ReadingLogModel> allLogs = [];

      // Firestore 'in' query limited to 10, so batch if needed
      for (var i = 0; i < studentIds.length; i += 10) {
        final batch = studentIds.skip(i).take(10).toList();
        final logsSnapshot = await _firebaseService.firestore
            .collection('schools')
            .doc(schoolId)
            .collection('readingLogs')
            .where('studentId', whereIn: batch)
            .where('date', isGreaterThanOrEqualTo: startDate)
            .where('date', isLessThanOrEqualTo: endDate)
            .get();

        allLogs.addAll(
          logsSnapshot.docs.map((doc) => ReadingLogModel.fromFirestore(doc)),
        );
      }

      return _calculateClassAnalytics(students, allLogs, startDate, endDate);
    } catch (e) {
      throw Exception('Error loading class analytics: $e');
    }
  }

  /// Get daily reading trends for visualization
  Future<List<DailyTrend>> getDailyTrends({
    required String schoolId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final logsSnapshot = await _firebaseService.firestore
          .collection('schools')
          .doc(schoolId)
          .collection('readingLogs')
          .where('date', isGreaterThanOrEqualTo: startDate)
          .where('date', isLessThanOrEqualTo: endDate)
          .get();

      final logs = logsSnapshot.docs
          .map((doc) => ReadingLogModel.fromFirestore(doc))
          .toList();

      return _calculateDailyTrends(logs, startDate, endDate);
    } catch (e) {
      throw Exception('Error loading daily trends: $e');
    }
  }

  /// Get engagement heatmap data (day of week analysis)
  Future<EngagementHeatmap> getEngagementHeatmap({
    required String schoolId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final logsSnapshot = await _firebaseService.firestore
          .collection('schools')
          .doc(schoolId)
          .collection('readingLogs')
          .where('date', isGreaterThanOrEqualTo: startDate)
          .where('date', isLessThanOrEqualTo: endDate)
          .get();

      final logs = logsSnapshot.docs
          .map((doc) => ReadingLogModel.fromFirestore(doc))
          .toList();

      return _calculateEngagementHeatmap(logs);
    } catch (e) {
      throw Exception('Error loading engagement heatmap: $e');
    }
  }

  // ============================================================================
  // Private Calculation Methods
  // ============================================================================

  SchoolAnalytics _calculateAnalytics(
    List<StudentModel> students,
    List<ReadingLogModel> logs,
    List<Map<String, dynamic>> classes,
    DateTime startDate,
    DateTime endDate,
  ) {
    final totalStudents = students.length;
    final totalMinutes = logs.fold(0, (sum, log) => sum + log.minutesRead);
    final totalBooks = logs.where((log) => log.bookCompleted).length;

    // Calculate active students (students who logged at least once)
    final activeStudentIds = logs.map((log) => log.studentId).toSet();
    final activeStudents = activeStudentIds.length;
    final engagementRate = totalStudents > 0
        ? ((activeStudents / totalStudents) * 100).round()
        : 0;

    // Calculate average metrics
    final avgMinutesPerStudent = activeStudents > 0
        ? (totalMinutes / activeStudents).round()
        : 0;
    final avgBooksPerStudent = activeStudents > 0
        ? (totalBooks / activeStudents).toStringAsFixed(1)
        : '0.0';

    // Calculate class metrics
    final classMetrics = <ClassMetric>[];
    for (final classData in classes) {
      final classStudents = students.where((s) => s.classId == classData['id']).toList();
      final classStudentIds = classStudents.map((s) => s.id).toSet();
      final classLogs = logs.where((log) => classStudentIds.contains(log.studentId)).toList();

      final classMinutes = classLogs.fold(0, (sum, log) => sum + log.minutesRead);
      final classBooks = classLogs.where((log) => log.bookCompleted).length;
      final classActive = classLogs.map((log) => log.studentId).toSet().length;

      classMetrics.add(ClassMetric(
        className: classData['name'] as String,
        classId: classData['id'] as String,
        totalStudents: classStudents.length,
        activeStudents: classActive,
        totalMinutes: classMinutes,
        totalBooks: classBooks,
        avgMinutesPerStudent: classActive > 0 ? (classMinutes / classActive).round() : 0,
      ));
    }

    // Sort classes by total minutes (descending)
    classMetrics.sort((a, b) => b.totalMinutes.compareTo(a.totalMinutes));

    // Calculate top readers
    final studentMinutes = <String, int>{};
    for (final log in logs) {
      studentMinutes[log.studentId] = (studentMinutes[log.studentId] ?? 0) + log.minutesRead;
    }

    final topReaderIds = studentMinutes.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final topReaders = topReaderIds.take(10).map((entry) {
      final student = students.firstWhere(
        (s) => s.id == entry.key,
        orElse: () => StudentModel(
          id: entry.key,
          schoolId: '',
          firstName: 'Unknown',
          lastName: 'Student',
          readingLevel: '',
          stats: StudentStats(),
          achievements: [],
          createdAt: DateTime.now(),
        ),
      );
      return TopReader(
        studentId: student.id,
        studentName: '${student.firstName} ${student.lastName}',
        className: _getClassName(student.classId, classes),
        minutesRead: entry.value,
      );
    }).toList();

    // Calculate achievement distribution
    final achievementCounts = <String, int>{};
    for (final student in students) {
      for (final achievement in student.achievements) {
        achievementCounts[achievement.rarity.name] =
            (achievementCounts[achievement.rarity.name] ?? 0) + 1;
      }
    }

    // Calculate growth (compare to previous period)
    // This would require historical data - simplified for now
    final growth = GrowthMetrics(
      minutesGrowth: 15, // Placeholder: 15% growth
      booksGrowth: 12, // Placeholder: 12% growth
      engagementGrowth: 8, // Placeholder: 8% growth
    );

    return SchoolAnalytics(
      totalStudents: totalStudents,
      activeStudents: activeStudents,
      engagementRate: engagementRate,
      totalMinutes: totalMinutes,
      totalBooks: totalBooks,
      avgMinutesPerStudent: avgMinutesPerStudent,
      avgBooksPerStudent: avgBooksPerStudent,
      classMetrics: classMetrics,
      topReaders: topReaders,
      achievementDistribution: achievementCounts,
      growth: growth,
      periodStart: startDate,
      periodEnd: endDate,
    );
  }

  ClassAnalytics _calculateClassAnalytics(
    List<StudentModel> students,
    List<ReadingLogModel> logs,
    DateTime startDate,
    DateTime endDate,
  ) {
    final totalStudents = students.length;
    final totalMinutes = logs.fold(0, (sum, log) => sum + log.minutesRead);
    final totalBooks = logs.where((log) => log.bookCompleted).length;

    final activeStudentIds = logs.map((log) => log.studentId).toSet();
    final activeStudents = activeStudentIds.length;

    // Calculate student-level metrics
    final studentMetrics = students.map((student) {
      final studentLogs = logs.where((log) => log.studentId == student.id).toList();
      final minutes = studentLogs.fold(0, (sum, log) => sum + log.minutesRead);
      final books = studentLogs.where((log) => log.bookCompleted).length;
      final days = studentLogs
          .map((log) => DateTime(log.date.year, log.date.month, log.date.day))
          .toSet()
          .length;

      return StudentMetric(
        studentId: student.id,
        studentName: '${student.firstName} ${student.lastName}',
        minutesRead: minutes,
        booksCompleted: books,
        daysActive: days,
        currentStreak: student.stats.currentStreak,
      );
    }).toList();

    // Sort by minutes read
    studentMetrics.sort((a, b) => b.minutesRead.compareTo(a.minutesRead));

    return ClassAnalytics(
      totalStudents: totalStudents,
      activeStudents: activeStudents,
      totalMinutes: totalMinutes,
      totalBooks: totalBooks,
      studentMetrics: studentMetrics,
      periodStart: startDate,
      periodEnd: endDate,
    );
  }

  List<DailyTrend> _calculateDailyTrends(
    List<ReadingLogModel> logs,
    DateTime startDate,
    DateTime endDate,
  ) {
    final dailyData = <DateTime, DailyData>{};

    // Initialize all days in range
    var currentDate = startDate;
    while (currentDate.isBefore(endDate) || currentDate.isAtSameMomentAs(endDate)) {
      final dateKey = DateTime(currentDate.year, currentDate.month, currentDate.day);
      dailyData[dateKey] = DailyData(minutes: 0, students: {}, books: 0);
      currentDate = currentDate.add(const Duration(days: 1));
    }

    // Aggregate logs by day
    for (final log in logs) {
      final dateKey = DateTime(log.date.year, log.date.month, log.date.day);
      if (dailyData.containsKey(dateKey)) {
        dailyData[dateKey]!.minutes += log.minutesRead;
        dailyData[dateKey]!.students.add(log.studentId);
        if (log.bookCompleted) {
          dailyData[dateKey]!.books += 1;
        }
      }
    }

    // Convert to list of trends
    final trends = dailyData.entries.map((entry) {
      return DailyTrend(
        date: entry.key,
        minutesRead: entry.value.minutes,
        activeStudents: entry.value.students.length,
        booksCompleted: entry.value.books,
      );
    }).toList();

    trends.sort((a, b) => a.date.compareTo(b.date));

    return trends;
  }

  EngagementHeatmap _calculateEngagementHeatmap(List<ReadingLogModel> logs) {
    // Count logs by day of week (0 = Monday, 6 = Sunday)
    final dayOfWeekCounts = List.filled(7, 0);
    final dayOfWeekMinutes = List.filled(7, 0);

    for (final log in logs) {
      final dayOfWeek = log.date.weekday - 1; // Convert to 0-indexed (Monday = 0)
      dayOfWeekCounts[dayOfWeek]++;
      dayOfWeekMinutes[dayOfWeek] += log.minutesRead;
    }

    final maxCount = dayOfWeekCounts.reduce((a, b) => a > b ? a : b);

    return EngagementHeatmap(
      dayLabels: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
      counts: dayOfWeekCounts,
      minutes: dayOfWeekMinutes,
      maxCount: maxCount,
    );
  }

  String _getClassName(String? classId, List<Map<String, dynamic>> classes) {
    if (classId == null) return 'No Class';
    final classData = classes.firstWhere(
      (c) => c['id'] == classId,
      orElse: () => {'name': 'Unknown Class'},
    );
    return classData['name'] as String;
  }
}

// ============================================================================
// Data Classes
// ============================================================================

class SchoolAnalytics {
  final int totalStudents;
  final int activeStudents;
  final int engagementRate; // Percentage
  final int totalMinutes;
  final int totalBooks;
  final int avgMinutesPerStudent;
  final String avgBooksPerStudent;
  final List<ClassMetric> classMetrics;
  final List<TopReader> topReaders;
  final Map<String, int> achievementDistribution;
  final GrowthMetrics growth;
  final DateTime periodStart;
  final DateTime periodEnd;

  SchoolAnalytics({
    required this.totalStudents,
    required this.activeStudents,
    required this.engagementRate,
    required this.totalMinutes,
    required this.totalBooks,
    required this.avgMinutesPerStudent,
    required this.avgBooksPerStudent,
    required this.classMetrics,
    required this.topReaders,
    required this.achievementDistribution,
    required this.growth,
    required this.periodStart,
    required this.periodEnd,
  });
}

class ClassMetric {
  final String className;
  final String classId;
  final int totalStudents;
  final int activeStudents;
  final int totalMinutes;
  final int totalBooks;
  final int avgMinutesPerStudent;

  ClassMetric({
    required this.className,
    required this.classId,
    required this.totalStudents,
    required this.activeStudents,
    required this.totalMinutes,
    required this.totalBooks,
    required this.avgMinutesPerStudent,
  });
}

class TopReader {
  final String studentId;
  final String studentName;
  final String className;
  final int minutesRead;

  TopReader({
    required this.studentId,
    required this.studentName,
    required this.className,
    required this.minutesRead,
  });
}

class GrowthMetrics {
  final int minutesGrowth; // Percentage
  final int booksGrowth; // Percentage
  final int engagementGrowth; // Percentage

  GrowthMetrics({
    required this.minutesGrowth,
    required this.booksGrowth,
    required this.engagementGrowth,
  });
}

class ClassAnalytics {
  final int totalStudents;
  final int activeStudents;
  final int totalMinutes;
  final int totalBooks;
  final List<StudentMetric> studentMetrics;
  final DateTime periodStart;
  final DateTime periodEnd;

  ClassAnalytics({
    required this.totalStudents,
    required this.activeStudents,
    required this.totalMinutes,
    required this.totalBooks,
    required this.studentMetrics,
    required this.periodStart,
    required this.periodEnd,
  });
}

class StudentMetric {
  final String studentId;
  final String studentName;
  final int minutesRead;
  final int booksCompleted;
  final int daysActive;
  final int currentStreak;

  StudentMetric({
    required this.studentId,
    required this.studentName,
    required this.minutesRead,
    required this.booksCompleted,
    required this.daysActive,
    required this.currentStreak,
  });
}

class DailyTrend {
  final DateTime date;
  final int minutesRead;
  final int activeStudents;
  final int booksCompleted;

  DailyTrend({
    required this.date,
    required this.minutesRead,
    required this.activeStudents,
    required this.booksCompleted,
  });
}

class DailyData {
  int minutes;
  Set<String> students;
  int books;

  DailyData({
    required this.minutes,
    required this.students,
    required this.books,
  });
}

class EngagementHeatmap {
  final List<String> dayLabels;
  final List<int> counts;
  final List<int> minutes;
  final int maxCount;

  EngagementHeatmap({
    required this.dayLabels,
    required this.counts,
    required this.minutes,
    required this.maxCount,
  });
}
