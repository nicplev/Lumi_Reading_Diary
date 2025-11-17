import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test helpers and utilities for Lumi Reading Diary tests

class TestHelpers {
  /// Create a fake Firestore instance for testing
  static FakeFirebaseFirestore createFakeFirestore() {
    return FakeFirebaseFirestore();
  }

  /// Create a mock Firebase Auth instance
  static MockFirebaseAuth createMockAuth() {
    return MockFirebaseAuth();
  }

  /// Create a timestamp for testing
  static Timestamp createTimestamp(DateTime dateTime) {
    return Timestamp.fromDate(dateTime);
  }

  /// Create a mock DocumentSnapshot
  static DocumentSnapshot<Map<String, dynamic>> createMockDocument({
    required String id,
    required Map<String, dynamic> data,
    required String collection,
    FakeFirebaseFirestore? firestore,
  }) {
    final fakeFirestore = firestore ?? createFakeFirestore();
    fakeFirestore.collection(collection).doc(id).set(data);
    return fakeFirestore.collection(collection).doc(id).get() as Future<DocumentSnapshot<Map<String, dynamic>>>;
  }

  /// Sample test data
  static Map<String, dynamic> sampleSchoolData({
    String? schoolId,
  }) {
    return {
      'id': schoolId ?? 'test-school-123',
      'name': 'Test Primary School',
      'levelSchema': 'A-Z',
      'customLevels': <String>[],
      'termDates': {
        'term1Start': Timestamp.fromDate(DateTime(2024, 1, 15)),
        'term1End': Timestamp.fromDate(DateTime(2024, 3, 28)),
      },
      'quietHours': {
        'enabled': true,
        'start': 20,
        'end': 7,
      },
      'timezone': 'America/New_York',
      'subscriptionPlan': 'premium',
      'subscriptionExpiry': Timestamp.fromDate(DateTime(2025, 12, 31)),
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
    };
  }

  static Map<String, dynamic> sampleStudentData({
    String? studentId,
    String? schoolId,
    String? classId,
  }) {
    return {
      'id': studentId ?? 'test-student-123',
      'firstName': 'Emma',
      'lastName': 'Watson',
      'studentId': 'STU001',
      'schoolId': schoolId ?? 'test-school-123',
      'classId': classId ?? 'test-class-123',
      'currentReadingLevel': 'Level 10',
      'parentIds': ['parent-123', 'parent-456'],
      'stats': {
        'totalMinutesRead': 450,
        'totalBooksRead': 15,
        'currentStreak': 7,
        'longestStreak': 14,
        'averageMinutesPerDay': 25.0,
        'totalReadingDays': 18,
        'lastReadingDate': Timestamp.now(),
      },
      'readingLevelHistory': [
        {
          'level': 'Level 10',
          'date': Timestamp.now(),
          'setBy': 'teacher-123',
        }
      ],
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
    };
  }

  static Map<String, dynamic> sampleReadingLogData({
    String? logId,
    String? studentId,
    String? parentId,
    String? schoolId,
  }) {
    return {
      'id': logId ?? 'test-log-123',
      'studentId': studentId ?? 'test-student-123',
      'parentId': parentId ?? 'parent-123',
      'schoolId': schoolId ?? 'test-school-123',
      'date': Timestamp.now(),
      'minutesRead': 25,
      'targetMinutes': 20,
      'bookTitles': ['Harry Potter', 'The Hobbit'],
      'notes': 'Great reading session!',
      'status': 'completed',
      'photoUrl': null,
      'isOfflineCreated': false,
      'syncedAt': Timestamp.now(),
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
    };
  }

  static Map<String, dynamic> sampleUserData({
    String? userId,
    String? schoolId,
    String role = 'teacher',
  }) {
    return {
      'id': userId ?? 'test-user-123',
      'email': 'teacher@testschool.com',
      'fullName': 'Sarah Johnson',
      'role': role,
      'schoolId': schoolId ?? 'test-school-123',
      'classIds': ['test-class-123', 'test-class-456'],
      'linkedChildren': role == 'parent' ? ['test-student-123'] : null,
      'fcmToken': 'test-fcm-token-123',
      'lastLogin': Timestamp.now(),
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
    };
  }

  static Map<String, dynamic> sampleClassData({
    String? classId,
    String? schoolId,
  }) {
    return {
      'id': classId ?? 'test-class-123',
      'schoolId': schoolId ?? 'test-school-123',
      'name': 'Year 3A',
      'yearLevel': '3',
      'room': 'Room 12',
      'teacherIds': ['teacher-123', 'teacher-456'],
      'studentIds': ['student-001', 'student-002', 'student-003'],
      'defaultMinutesTarget': 20,
      'stats': {
        'totalMinutesRead': 1500,
        'totalBooksRead': 45,
        'activeStudents': 3,
      },
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
    };
  }

  static Map<String, dynamic> sampleAllocationData({
    String? allocationId,
    String? schoolId,
    String? classId,
  }) {
    return {
      'id': allocationId ?? 'test-allocation-123',
      'schoolId': schoolId ?? 'test-school-123',
      'classId': classId ?? 'test-class-123',
      'createdBy': 'teacher-123',
      'type': 'byLevel',
      'cadence': 'daily',
      'targetMinutes': 20,
      'levelStart': 'Level 8',
      'levelEnd': 'Level 12',
      'bookTitles': <String>[],
      'studentIds': ['student-001', 'student-002'],
      'startDate': Timestamp.now(),
      'endDate': Timestamp.fromDate(DateTime.now().add(const Duration(days: 30))),
      'isActive': true,
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
    };
  }

  static Map<String, dynamic> sampleLinkCodeData({
    String? codeId,
    String? studentId,
  }) {
    return {
      'id': codeId ?? 'test-code-123',
      'code': 'ABC123XY',
      'studentId': studentId ?? 'test-student-123',
      'schoolId': 'test-school-123',
      'status': 'active',
      'createdBy': 'teacher-123',
      'createdAt': Timestamp.now(),
      'expiryDate': Timestamp.fromDate(DateTime.now().add(const Duration(days: 365))),
      'usedBy': null,
      'usedAt': null,
      'revokedBy': null,
      'revokedAt': null,
    };
  }
}

/// Extensions for testing
extension TestTimestampExtension on DateTime {
  Timestamp toTimestamp() {
    return Timestamp.fromDate(this);
  }
}

/// Matchers for custom objects
class HasProperty extends Matcher {
  final String property;
  final dynamic value;

  HasProperty(this.property, this.value);

  @override
  bool matches(dynamic item, Map matchState) {
    if (item is Map) {
      return item[property] == value;
    }
    return false;
  }

  @override
  Description describe(Description description) {
    return description.add('has property "$property" with value "$value"');
  }
}

Matcher hasProperty(String property, dynamic value) => HasProperty(property, value);
