import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class DailyStudentReadingMetrics {
  const DailyStudentReadingMetrics({
    required this.logs,
    required this.minutes,
    required this.teacherLogs,
  });

  final int logs;
  final int minutes;
  final int teacherLogs;

  DailyStudentReadingMetrics add(DailyStudentReadingMetrics other) =>
      DailyStudentReadingMetrics(
        logs: logs + other.logs,
        minutes: minutes + other.minutes,
        teacherLogs: teacherLogs + other.teacherLogs,
      );
}

class ClassDailyReadingSummary {
  const ClassDailyReadingSummary({
    required this.localDate,
    required this.logCount,
    required this.totalMinutes,
    required this.teacherLogCount,
    required this.students,
  });

  final String localDate;
  final int logCount;
  final int totalMinutes;
  final int teacherLogCount;
  final Map<String, DailyStudentReadingMetrics> students;

  DateTime get date => DateTime.parse(localDate);
  int get activeStudentCount => students.length;

  ClassDailyReadingSummary merge(ClassDailyReadingSummary other) {
    final mergedStudents = {...students};
    for (final entry in other.students.entries) {
      mergedStudents.update(
        entry.key,
        (current) => current.add(entry.value),
        ifAbsent: () => entry.value,
      );
    }
    return ClassDailyReadingSummary(
      localDate: localDate,
      logCount: logCount + other.logCount,
      totalMinutes: totalMinutes + other.totalMinutes,
      teacherLogCount: teacherLogCount + other.teacherLogCount,
      students: mergedStudents,
    );
  }
}

/// Reads server-owned class/day summary shards and merges them per local day.
class ClassDailyReadingService {
  ClassDailyReadingService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static String dateKey(DateTime date) => DateFormat('yyyy-MM-dd')
      .format(DateTime(date.year, date.month, date.day));

  Query<Map<String, dynamic>> _rangeQuery({
    required String schoolId,
    required String classId,
    required DateTime startInclusive,
    required DateTime endInclusive,
  }) {
    return _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('classDailyReading')
        .where('classId', isEqualTo: classId)
        .where('localDate', isGreaterThanOrEqualTo: dateKey(startInclusive))
        .where('localDate', isLessThanOrEqualTo: dateKey(endInclusive))
        .orderBy('localDate');
  }

  Stream<List<ClassDailyReadingSummary>> watchRange({
    required String schoolId,
    required String classId,
    required DateTime startInclusive,
    required DateTime endInclusive,
  }) {
    return _rangeQuery(
      schoolId: schoolId,
      classId: classId,
      startInclusive: startInclusive,
      endInclusive: endInclusive,
    ).snapshots().map(_mergeSnapshot);
  }

  Future<List<ClassDailyReadingSummary>> fetchRange({
    required String schoolId,
    required String classId,
    required DateTime startInclusive,
    required DateTime endInclusive,
  }) async {
    final snapshot = await _rangeQuery(
      schoolId: schoolId,
      classId: classId,
      startInclusive: startInclusive,
      endInclusive: endInclusive,
    ).get(const GetOptions(source: Source.serverAndCache));
    return _mergeSnapshot(snapshot);
  }

  List<ClassDailyReadingSummary> _mergeSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final byDate = <String, ClassDailyReadingSummary>{};
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final localDate = data['localDate'] as String?;
      if (localDate == null || data['classId'] is! String) continue;
      try {
        DateTime.parse(localDate);
      } catch (_) {
        continue;
      }
      final students = <String, DailyStudentReadingMetrics>{};
      final rawStudents = data['students'];
      if (rawStudents is Map) {
        for (final entry in rawStudents.entries) {
          if (entry.key is! String || entry.value is! Map) continue;
          final raw = entry.value as Map;
          final logs = (raw['logs'] as num?)?.toInt() ?? 0;
          if (logs <= 0) continue;
          students[entry.key as String] = DailyStudentReadingMetrics(
            logs: logs,
            minutes: (raw['minutes'] as num?)?.toInt() ?? 0,
            teacherLogs: (raw['teacherLogs'] as num?)?.toInt() ?? 0,
          );
        }
      }
      final shard = ClassDailyReadingSummary(
        localDate: localDate,
        logCount: (data['logCount'] as num?)?.toInt() ?? 0,
        totalMinutes: (data['totalMinutes'] as num?)?.toInt() ?? 0,
        teacherLogCount: (data['teacherLogCount'] as num?)?.toInt() ?? 0,
        students: students,
      );
      byDate.update(
        localDate,
        (current) => current.merge(shard),
        ifAbsent: () => shard,
      );
    }
    final summaries = byDate.values.toList()
      ..sort((a, b) => a.localDate.compareTo(b.localDate));
    return summaries;
  }
}
