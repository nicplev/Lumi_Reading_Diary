import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Debug utility to inspect Firestore structure and verify data exists
class FirestoreDebug {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Check if students exist in the database for a given school
  Future<Map<String, dynamic>> checkStudentsExist(String schoolId) async {
    try {
      debugPrint('🔍 Checking for students in school: $schoolId');

      // Query nested structure: schools/{schoolId}/students
      final studentsSnapshot = await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('students')
          .get();

      debugPrint('📊 Found ${studentsSnapshot.docs.length} student documents');

      final students = studentsSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'studentId': data['studentId'],
          'firstName': data['firstName'],
          'lastName': data['lastName'],
          'classId': data['classId'],
          'isActive': data['isActive'],
        };
      }).toList();

      // Log each student found
      for (final student in students) {
        debugPrint('   ✓ ${student['firstName']} ${student['lastName']} (${student['studentId']}) - classId: ${student['classId']}');
      }

      return {
        'success': true,
        'count': studentsSnapshot.docs.length,
        'students': students,
        'path': 'schools/$schoolId/students',
      };
    } catch (e, stackTrace) {
      debugPrint('❌ Error checking students: $e');
      debugPrint('Stack trace: $stackTrace');
      return {
        'success': false,
        'error': e.toString(),
        'count': 0,
        'students': [],
      };
    }
  }

  /// Check classes and their student arrays
  Future<Map<String, dynamic>> checkClassesWithStudents(String schoolId) async {
    try {
      debugPrint('🔍 Checking classes in school: $schoolId');

      final classesSnapshot = await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('classes')
          .get();

      debugPrint('📊 Found ${classesSnapshot.docs.length} class documents');

      final classes = <Map<String, dynamic>>[];

      for (final doc in classesSnapshot.docs) {
        final data = doc.data();
        final studentIds = List<String>.from(data['studentIds'] ?? []);

        classes.add({
          'id': doc.id,
          'name': data['name'],
          'yearLevel': data['yearLevel'],
          'studentCount': studentIds.length,
          'studentIds': studentIds,
        });

        debugPrint('   ✓ ${data['name']} (${data['yearLevel']}) - ${studentIds.length} students');
        for (final studentId in studentIds) {
          debugPrint('      - Student ID: $studentId');
        }
      }

      return {
        'success': true,
        'count': classesSnapshot.docs.length,
        'classes': classes,
        'path': 'schools/$schoolId/classes',
      };
    } catch (e, stackTrace) {
      debugPrint('❌ Error checking classes: $e');
      debugPrint('Stack trace: $stackTrace');
      return {
        'success': false,
        'error': e.toString(),
        'count': 0,
        'classes': [],
      };
    }
  }

  /// Verify student documents exist for IDs referenced in classes
  Future<Map<String, dynamic>> verifyStudentReferences(String schoolId) async {
    try {
      debugPrint('🔍 Verifying student references for school: $schoolId');

      // Get all classes
      final classesResult = await checkClassesWithStudents(schoolId);
      final classes = classesResult['classes'] as List<Map<String, dynamic>>;

      // Collect all student IDs from classes
      final allStudentIds = <String>{};
      for (final classData in classes) {
        final studentIds = classData['studentIds'] as List<String>;
        allStudentIds.addAll(studentIds);
      }

      debugPrint('📋 Found ${allStudentIds.length} unique student IDs in class arrays');

      // Check if each student document exists
      final missingStudents = <String>[];
      final existingStudents = <Map<String, dynamic>>[];

      for (final studentId in allStudentIds) {
        final studentDoc = await _firestore
            .collection('schools')
            .doc(schoolId)
            .collection('students')
            .doc(studentId)
            .get();

        if (studentDoc.exists) {
          final data = studentDoc.data()!;
          existingStudents.add({
            'id': studentId,
            'studentId': data['studentId'],
            'firstName': data['firstName'],
            'lastName': data['lastName'],
          });
          debugPrint('   ✓ Student document exists: ${data['firstName']} ${data['lastName']}');
        } else {
          missingStudents.add(studentId);
          debugPrint('   ❌ Student document MISSING: $studentId');
        }
      }

      return {
        'success': true,
        'totalReferences': allStudentIds.length,
        'existingCount': existingStudents.length,
        'missingCount': missingStudents.length,
        'existing': existingStudents,
        'missing': missingStudents,
      };
    } catch (e, stackTrace) {
      debugPrint('❌ Error verifying student references: $e');
      debugPrint('Stack trace: $stackTrace');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Run a complete diagnostic check
  Future<Map<String, dynamic>> runFullDiagnostic(String schoolId) async {
    debugPrint('🏥 Running full diagnostic for school: $schoolId');
    debugPrint('═══════════════════════════════════════════════════');

    final studentsResult = await checkStudentsExist(schoolId);
    debugPrint('');

    final classesResult = await checkClassesWithStudents(schoolId);
    debugPrint('');

    final verificationResult = await verifyStudentReferences(schoolId);
    debugPrint('');

    debugPrint('═══════════════════════════════════════════════════');
    debugPrint('📈 DIAGNOSTIC SUMMARY:');
    debugPrint('   Students in database: ${studentsResult['count']}');
    debugPrint('   Classes in database: ${classesResult['count']}');
    debugPrint('   Student references in classes: ${verificationResult['totalReferences']}');
    debugPrint('   Existing student documents: ${verificationResult['existingCount']}');
    debugPrint('   Missing student documents: ${verificationResult['missingCount']}');
    debugPrint('═══════════════════════════════════════════════════');

    return {
      'students': studentsResult,
      'classes': classesResult,
      'verification': verificationResult,
    };
  }

  /// Create a test student for debugging
  Future<Map<String, dynamic>> createTestStudent(String schoolId, String classId) async {
    try {
      debugPrint('🧪 Creating test student');

      final studentRef = _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('students')
          .doc();

      final studentData = {
        'studentId': 'TEST${DateTime.now().millisecondsSinceEpoch}',
        'firstName': 'Test',
        'lastName': 'Student',
        'schoolId': schoolId,
        'classId': classId,
        'dateOfBirth': null,
        'currentReadingLevel': 'Level A',
        'parentIds': <String>[],
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'enrolledAt': FieldValue.serverTimestamp(),
        'profileImageUrl': null,
        'additionalInfo': {'note': 'Test student for debugging'},
        'levelHistory': [],
        'stats': {
          'totalMinutesRead': 0,
          'totalBooksRead': 0,
          'currentStreak': 0,
          'longestStreak': 0,
          'lastReadingDate': null,
        },
      };

      await studentRef.set(studentData);

      // Add student ID to class
      final classRef = _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('classes')
          .doc(classId);

      await classRef.update({
        'studentIds': FieldValue.arrayUnion([studentRef.id]),
      });

      debugPrint('✅ Test student created with ID: ${studentRef.id}');

      return {
        'success': true,
        'studentId': studentRef.id,
        'studentData': studentData,
      };
    } catch (e, stackTrace) {
      debugPrint('❌ Error creating test student: $e');
      debugPrint('Stack trace: $stackTrace');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Fix student documents that are missing isActive field
  Future<Map<String, dynamic>> fixStudentActiveStatus(String schoolId) async {
    try {
      debugPrint('🔧 Fixing student active status for school: $schoolId');

      final studentsSnapshot = await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('students')
          .get();

      final batch = _firestore.batch();
      final fixedStudents = <Map<String, dynamic>>[];
      int fixedCount = 0;

      for (final doc in studentsSnapshot.docs) {
        final data = doc.data();
        final isActive = data['isActive'];

        // Fix if isActive is null or not explicitly true
        if (isActive == null || isActive != true) {
          batch.update(doc.reference, {'isActive': true});
          fixedStudents.add({
            'id': doc.id,
            'studentId': data['studentId'],
            'firstName': data['firstName'],
            'lastName': data['lastName'],
            'previousStatus': isActive,
          });
          fixedCount++;
          debugPrint('   ✓ Fixed ${data['firstName']} ${data['lastName']} - was: $isActive, now: true');
        }
      }

      if (fixedCount > 0) {
        await batch.commit();
        debugPrint('✅ Fixed $fixedCount student(s)');
      } else {
        debugPrint('✓ All students already have isActive set correctly');
      }

      return {
        'success': true,
        'fixedCount': fixedCount,
        'totalStudents': studentsSnapshot.docs.length,
        'fixedStudents': fixedStudents,
      };
    } catch (e, stackTrace) {
      debugPrint('❌ Error fixing student active status: $e');
      debugPrint('Stack trace: $stackTrace');
      return {
        'success': false,
        'error': e.toString(),
        'fixedCount': 0,
      };
    }
  }

  /// Clean up classes with null names
  Future<Map<String, dynamic>> cleanupNullClasses(String schoolId) async {
    try {
      debugPrint('🧹 Cleaning up null-named classes for school: $schoolId');

      final classesSnapshot = await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('classes')
          .get();

      final batch = _firestore.batch();
      final deletedClasses = <String>[];
      int deletedCount = 0;

      for (final doc in classesSnapshot.docs) {
        final data = doc.data();
        final name = data['name'];
        final studentIds = List<String>.from(data['studentIds'] ?? []);

        // Delete if name is null and class is empty
        if (name == null && studentIds.isEmpty) {
          batch.delete(doc.reference);
          deletedClasses.add(doc.id);
          deletedCount++;
          debugPrint('   ✓ Deleted empty class with null name: ${doc.id}');
        }
      }

      if (deletedCount > 0) {
        await batch.commit();
        debugPrint('✅ Deleted $deletedCount empty class(es) with null names');
      } else {
        debugPrint('✓ No empty null-named classes to clean up');
      }

      return {
        'success': true,
        'deletedCount': deletedCount,
        'totalClasses': classesSnapshot.docs.length,
        'deletedClasses': deletedClasses,
      };
    } catch (e, stackTrace) {
      debugPrint('❌ Error cleaning up classes: $e');
      debugPrint('Stack trace: $stackTrace');
      return {
        'success': false,
        'error': e.toString(),
        'deletedCount': 0,
      };
    }
  }
}
