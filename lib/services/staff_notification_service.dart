import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../data/models/class_model.dart';
import '../data/models/notification_campaign_model.dart';
import '../data/models/parent_notification_model.dart';
import '../data/models/student_model.dart';
import '../data/models/user_model.dart';

class StaffNotificationException implements Exception {
  final String message;

  StaffNotificationException(this.message);

  @override
  String toString() => message;
}

class StaffNotificationService {
  StaffNotificationService._();

  static final StaffNotificationService instance = StaffNotificationService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  CollectionReference<Map<String, dynamic>> _campaigns(String schoolId) {
    return _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('notificationCampaigns');
  }

  CollectionReference<Map<String, dynamic>> _classes(String schoolId) {
    return _firestore.collection('schools').doc(schoolId).collection('classes');
  }

  CollectionReference<Map<String, dynamic>> _students(String schoolId) {
    return _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('students');
  }

  CollectionReference<Map<String, dynamic>> _parentNotifications(
    UserModel user,
  ) {
    return _firestore
        .collection('schools')
        .doc(user.schoolId)
        .collection('parents')
        .doc(user.id)
        .collection('notifications');
  }

  Stream<List<NotificationCampaignModel>> watchCampaigns(UserModel user) {
    if (user.schoolId == null || user.schoolId!.isEmpty) {
      return Stream<List<NotificationCampaignModel>>.value(const []);
    }

    Query<Map<String, dynamic>> query =
        _campaigns(user.schoolId!).orderBy('createdAt', descending: true);

    if (user.role == UserRole.teacher) {
      query = _campaigns(user.schoolId!)
          .where('createdBy', isEqualTo: user.id)
          .orderBy('createdAt', descending: true);
    }

    return query.snapshots().map(
          (snapshot) => snapshot.docs
              .map(NotificationCampaignModel.fromFirestore)
              .toList(),
        );
  }

  Stream<List<ParentNotificationModel>> watchParentNotifications(
      UserModel user) {
    if (user.schoolId == null || user.schoolId!.isEmpty) {
      return Stream<List<ParentNotificationModel>>.value(const []);
    }

    return _parentNotifications(user)
        .orderBy('deliveredAt', descending: true)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(ParentNotificationModel.fromFirestore).toList(),
        );
  }

  Stream<int> watchUnreadParentNotificationCount(UserModel user) {
    if (user.schoolId == null || user.schoolId!.isEmpty) {
      return Stream<int>.value(0);
    }

    return _parentNotifications(user)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.size);
  }

  Future<void> markParentNotificationRead({
    required UserModel user,
    required String notificationId,
  }) async {
    await _parentNotifications(user).doc(notificationId).update({
      'isRead': true,
      'readAt': FieldValue.serverTimestamp(),
    });
  }

  Future<List<ClassModel>> loadAvailableClasses(UserModel user) async {
    final schoolId = user.schoolId;
    if (schoolId == null || schoolId.isEmpty) return const [];

    Query<Map<String, dynamic>> query =
        _classes(schoolId).where('isActive', isEqualTo: true).orderBy('name');

    if (user.role == UserRole.teacher) {
      query = _classes(schoolId)
          .where('teacherIds', arrayContains: user.id)
          .where('isActive', isEqualTo: true);
    }

    final snapshot = await query.get();
    return snapshot.docs.map(ClassModel.fromFirestore).toList();
  }

  Future<List<StudentModel>> loadAvailableStudents(
    UserModel user, {
    List<String>? classIds,
  }) async {
    final schoolId = user.schoolId;
    if (schoolId == null || schoolId.isEmpty) return const [];

    final effectiveClassIds =
        (classIds ?? []).where((id) => id.isNotEmpty).toList();

    if (effectiveClassIds.length == 1) {
      final snapshot = await _students(schoolId)
          .where('classId', isEqualTo: effectiveClassIds.first)
          .where('isActive', isEqualTo: true)
          .orderBy('firstName')
          .get();
      return snapshot.docs.map(StudentModel.fromFirestore).toList();
    }

    if (effectiveClassIds.length > 1) {
      final results = <StudentModel>[];
      for (var i = 0; i < effectiveClassIds.length; i += 30) {
        final chunk = effectiveClassIds.skip(i).take(30).toList();
        final snapshot = await _students(schoolId)
            .where('classId', whereIn: chunk)
            .where('isActive', isEqualTo: true)
            .orderBy('firstName')
            .get();
        results.addAll(snapshot.docs.map(StudentModel.fromFirestore));
      }
      return results;
    }

    if (user.role == UserRole.teacher) {
      final classes = await loadAvailableClasses(user);
      if (classes.isEmpty) return const [];
      return loadAvailableStudents(
        user,
        classIds: classes.map((classModel) => classModel.id).toList(),
      );
    }

    final snapshot = await _students(schoolId)
        .where('isActive', isEqualTo: true)
        .orderBy('firstName')
        .get();
    return snapshot.docs.map(StudentModel.fromFirestore).toList();
  }

  Future<String> createCampaign({
    required UserModel user,
    required String title,
    required String body,
    required String messageType,
    required String audienceType,
    required List<String> classIds,
    required List<String> studentIds,
    DateTime? scheduledFor,
  }) async {
    final schoolId = user.schoolId;
    if (schoolId == null || schoolId.isEmpty) {
      throw StaffNotificationException('School context is missing.');
    }

    try {
      final callable = _functions.httpsCallable('createNotificationCampaign');
      final result = await callable.call({
        'schoolId': schoolId,
        'title': title.trim(),
        'body': body.trim(),
        'messageType': messageType,
        'audienceType': audienceType,
        'classIds': classIds,
        'studentIds': studentIds,
        'scheduledFor': scheduledFor?.millisecondsSinceEpoch,
      });

      final data = result.data as Map<Object?, Object?>;
      return data['campaignId'] as String;
    } on FirebaseFunctionsException catch (error) {
      throw StaffNotificationException(
        error.message ?? 'Unable to create notification campaign.',
      );
    }
  }
}
