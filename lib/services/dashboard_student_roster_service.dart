import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/models/student_model.dart';

/// A successfully parsed dashboard student plus the raw achievement payloads
/// already present on the same Firestore document.
class DashboardRosterStudent {
  const DashboardRosterStudent({
    required this.student,
    required this.achievementData,
  });

  final StudentModel student;
  final List<dynamic> achievementData;
}

/// Result of resolving the denormalised class roster against student docs.
///
/// A class can temporarily contain a stale id after interrupted imports,
/// rollovers, or legacy deletion paths. Those ids are reported but never make
/// valid classmates disappear from the result.
class DashboardStudentRosterResult {
  const DashboardStudentRosterResult({
    required this.entries,
    required this.unresolvedStudentIds,
    required this.malformedStudentIds,
  });

  final List<DashboardRosterStudent> entries;
  final Set<String> unresolvedStudentIds;
  final Set<String> malformedStudentIds;

  int get warningCount =>
      unresolvedStudentIds.length + malformedStudentIds.length;
}

/// Loads the student identities used by teacher dashboard widgets.
///
/// The query is constrained by `classId`, which is the condition Firestore
/// Security Rules use to prove that the signed-in teacher owns the class. We
/// deliberately do not add a document-id `in` filter from `class.studentIds`:
/// one dangling id would make Rules evaluate a missing resource and deny the
/// entire batch. Instead, the server-authorised class query is intersected
/// with the roster locally after the read.
class DashboardStudentRosterService {
  DashboardStudentRosterService({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  Future<DashboardStudentRosterResult> fetch({
    required String schoolId,
    required String classId,
    required List<String> rosterStudentIds,
  }) async {
    final orderedRosterIds = <String>[];
    final rosterIds = <String>{};
    for (final rawId in rosterStudentIds) {
      final id = rawId.trim();
      if (id.isNotEmpty && rosterIds.add(id)) orderedRosterIds.add(id);
    }

    if (rosterIds.isEmpty) {
      return const DashboardStudentRosterResult(
        entries: [],
        unresolvedStudentIds: {},
        malformedStudentIds: {},
      );
    }

    final snapshot = await _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('students')
        .where('classId', isEqualTo: classId)
        .get();

    final entriesById = <String, DashboardRosterStudent>{};
    final resolvedDocumentIds = <String>{};
    final malformedStudentIds = <String>{};

    for (final doc in snapshot.docs) {
      if (!rosterIds.contains(doc.id)) continue;
      resolvedDocumentIds.add(doc.id);

      try {
        final student = StudentModel.fromFirestore(doc);
        // Treat cross-school/class identity drift as malformed even if a fake
        // or legacy backend returns it. The query and document path remain the
        // security boundary; this is an additional display-integrity guard.
        if (student.schoolId != schoolId || student.classId != classId) {
          malformedStudentIds.add(doc.id);
          continue;
        }

        final rawAchievements = doc.data()['achievements'];
        entriesById[doc.id] = DashboardRosterStudent(
          student: student,
          achievementData: rawAchievements is List
              ? List<dynamic>.unmodifiable(rawAchievements)
              : const [],
        );
      } catch (_) {
        // One malformed profile must not blank every valid student on the
        // dashboard. The caller receives the count for UI/telemetry.
        malformedStudentIds.add(doc.id);
      }
    }

    return DashboardStudentRosterResult(
      entries: [
        for (final id in orderedRosterIds)
          if (entriesById[id] case final entry?) entry,
      ],
      unresolvedStudentIds: rosterIds.difference(resolvedDocumentIds),
      malformedStudentIds: malformedStudentIds,
    );
  }
}
