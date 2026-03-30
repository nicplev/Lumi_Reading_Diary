import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/models/reading_level_event.dart';
import '../data/models/reading_level_option.dart';
import '../data/models/student_model.dart';
import '../data/models/user_model.dart';
import 'firebase_service.dart';
import 'reading_level_service.dart';

class StudentReadingLevelService {
  StudentReadingLevelService({
    FirebaseFirestore? firestore,
    ReadingLevelService? readingLevelService,
  })  : _firestore = firestore ?? FirebaseService.instance.firestore,
        _readingLevelService = readingLevelService ??
            ReadingLevelService(
                firestore: firestore ?? FirebaseService.instance.firestore);

  static const String sourceTeacher = 'teacher';
  static const String sourceSchoolAdmin = 'schoolAdmin';
  static const String sourceBulkTeacher = 'bulkTeacher';

  final FirebaseFirestore _firestore;
  final ReadingLevelService _readingLevelService;

  Future<bool> updateStudentLevel({
    required UserModel actor,
    required StudentModel student,
    required List<ReadingLevelOption> options,
    String? newLevel,
    String? reason,
    String? source,
  }) async {
    final effectiveSource = source ?? _sourceForActor(actor);
    final changeSet = _buildChangeSet(
      actor: actor,
      student: student,
      options: options,
      newLevel: newLevel,
      reason: reason,
      effectiveSource: effectiveSource,
    );

    if (changeSet == null) {
      return false;
    }

    final batch = _firestore.batch();
    batch.update(changeSet.studentRef, changeSet.studentUpdate);
    batch.set(changeSet.eventRef, changeSet.eventData);
    await batch.commit();
    return true;
  }

  Future<int> bulkUpdateStudentLevels({
    required UserModel actor,
    required List<StudentModel> students,
    required List<ReadingLevelOption> options,
    String? newLevel,
    String? reason,
    String? source,
  }) async {
    if (students.isEmpty) return 0;

    final effectiveSource = source ?? _sourceForActor(actor);
    final changeSets = students
        .map(
          (student) => _buildChangeSet(
            actor: actor,
            student: student,
            options: options,
            newLevel: newLevel,
            reason: reason,
            effectiveSource: effectiveSource,
          ),
        )
        .whereType<_ReadingLevelChangeSet>()
        .toList(growable: false);

    if (changeSets.isEmpty) {
      return 0;
    }

    const maxStudentsPerBatch = 200;
    for (int i = 0; i < changeSets.length; i += maxStudentsPerBatch) {
      final batch = _firestore.batch();
      for (final changeSet in changeSets.skip(i).take(maxStudentsPerBatch)) {
        batch.update(changeSet.studentRef, changeSet.studentUpdate);
        batch.set(changeSet.eventRef, changeSet.eventData);
      }
      await batch.commit();
    }
    return changeSets.length;
  }

  _ReadingLevelChangeSet? _buildChangeSet({
    required UserModel actor,
    required StudentModel student,
    required List<ReadingLevelOption> options,
    required String? newLevel,
    required String? reason,
    required String effectiveSource,
  }) {
    final trimmedCurrent = student.currentReadingLevel?.trim();
    final normalizedCurrent = _readingLevelService.normalizeLevel(
      trimmedCurrent,
      options: options,
    );
    final normalizedNext = _readingLevelService.normalizeLevel(
      newLevel,
      options: options,
    );
    final hasUnresolvedCurrent = trimmedCurrent != null &&
        trimmedCurrent.isNotEmpty &&
        normalizedCurrent == null;

    if (!hasUnresolvedCurrent && normalizedCurrent == normalizedNext) {
      return null;
    }

    final now = DateTime.now();
    final studentRef = _firestore
        .collection('schools')
        .doc(student.schoolId)
        .collection('students')
        .doc(student.id);
    final eventRef = studentRef.collection('readingLevelEvents').doc();
    final fromLevel = normalizedCurrent ?? trimmedCurrent;
    final fromLevelIndex = _readingLevelService.sortIndexForLevel(
      normalizedCurrent,
      options: options,
    );
    final toLevelIndex = _readingLevelService.sortIndexForLevel(
      normalizedNext,
      options: options,
    );
    final cleanedReason = reason?.trim();

    final studentUpdate = <String, dynamic>{
      'currentReadingLevel': normalizedNext,
      'currentReadingLevelIndex': toLevelIndex,
      'readingLevelUpdatedAt': FieldValue.serverTimestamp(),
      'readingLevelUpdatedBy': actor.id,
      'readingLevelSource': effectiveSource,
    };

    final eventData = <String, dynamic>{
      'studentId': student.id,
      'schoolId': student.schoolId,
      'classId': student.classId,
      'fromLevel': fromLevel,
      'toLevel': normalizedNext,
      'fromLevelIndex': fromLevelIndex,
      'toLevelIndex': toLevelIndex,
      'source': effectiveSource,
      'changedByUserId': actor.id,
      'changedByRole': actor.role.toString().split('.').last,
      'changedByName': actor.fullName,
      'createdAt': FieldValue.serverTimestamp(),
    };

    if (cleanedReason != null && cleanedReason.isNotEmpty) {
      eventData['reason'] = cleanedReason;
    }

    if (normalizedNext != null && normalizedNext.isNotEmpty) {
      final legacyHistoryEntry = <String, dynamic>{
        'level': normalizedNext,
        'changedAt': Timestamp.fromDate(now),
        'changedBy': actor.id,
      };
      if (cleanedReason != null && cleanedReason.isNotEmpty) {
        legacyHistoryEntry['reason'] = cleanedReason;
      }
      studentUpdate['levelHistory'] =
          FieldValue.arrayUnion([legacyHistoryEntry]);
    }

    return _ReadingLevelChangeSet(
      studentRef: studentRef,
      eventRef: eventRef,
      studentUpdate: studentUpdate,
      eventData: eventData,
    );
  }

  Stream<List<ReadingLevelEvent>> watchReadingLevelEvents({
    required String schoolId,
    required String studentId,
    int limit = 30,
  }) {
    return _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('students')
        .doc(studentId)
        .collection('readingLevelEvents')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(ReadingLevelEvent.fromFirestore)
              .toList(growable: false),
        );
  }

  String _sourceForActor(UserModel actor) {
    switch (actor.role) {
      case UserRole.teacher:
        return sourceTeacher;
      case UserRole.schoolAdmin:
        return sourceSchoolAdmin;
      case UserRole.parent:
        return sourceTeacher;
    }
  }
}

class _ReadingLevelChangeSet {
  const _ReadingLevelChangeSet({
    required this.studentRef,
    required this.eventRef,
    required this.studentUpdate,
    required this.eventData,
  });

  final DocumentReference<Map<String, dynamic>> studentRef;
  final DocumentReference<Map<String, dynamic>> eventRef;
  final Map<String, dynamic> studentUpdate;
  final Map<String, dynamic> eventData;
}
