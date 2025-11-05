import 'package:cloud_firestore/cloud_firestore.dart';

/// Migration utility to restructure Firestore from flat collections to nested school-based structure
///
/// OLD STRUCTURE:
/// /users (all users)
/// /students (all students)
/// /classes (all classes)
/// /readingLogs (all logs)
///
/// NEW STRUCTURE:
/// /schools/{schoolId}/
///   - info (document with school details)
///   - /users/{userId} (staff, admin, teachers)
///   - /students/{studentId}
///   - /classes/{classId}
///   - /parents/{parentId}
///   - /readingLogs/{logId}
class FirestoreMigration {
  final FirebaseFirestore firestore;

  FirestoreMigration({FirebaseFirestore? firestore})
      : firestore = firestore ?? FirebaseFirestore.instance;

  /// Main migration method - call this to migrate all data
  Future<void> migrateToNestedStructure() async {
    try {
      print('Starting Firestore migration to nested structure...');

      // Step 1: Get all schools
      final schoolsSnapshot = await firestore.collection('schools').get();
      print('Found ${schoolsSnapshot.docs.length} schools to migrate');

      for (final schoolDoc in schoolsSnapshot.docs) {
        final schoolId = schoolDoc.id;
        final schoolData = schoolDoc.data();
        print('\nMigrating school: $schoolId');

        // Step 2: Create school info document in new structure
        await _migrateSchoolInfo(schoolId, schoolData);

        // Step 3: Migrate users for this school
        await _migrateUsersForSchool(schoolId);

        // Step 4: Migrate students for this school
        await _migrateStudentsForSchool(schoolId);

        // Step 5: Migrate classes for this school
        await _migrateClassesForSchool(schoolId);

        // Step 6: Migrate reading logs for this school
        await _migrateReadingLogsForSchool(schoolId);

        print('✓ Completed migration for school: $schoolId');
      }

      // Step 7: Migrate parent users separately (they might not have schoolId)
      await _migrateParentUsers();

      print('\n✅ Migration completed successfully!');
      print(
          'Note: Old collections still exist. Delete them manually after verifying migration.');
    } catch (e) {
      print('❌ Migration failed: $e');
      rethrow;
    }
  }

  /// Migrate school info document
  Future<void> _migrateSchoolInfo(
      String schoolId, Map<String, dynamic> schoolData) async {
    try {
      // Create the school document with info subdocument
      await firestore.collection('schools').doc(schoolId).set({
        ...schoolData,
        'migratedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print('  ✓ Migrated school info');
    } catch (e) {
      print('  ✗ Failed to migrate school info: $e');
      rethrow;
    }
  }

  /// Migrate all users (staff, admin, teachers) for a specific school
  Future<void> _migrateUsersForSchool(String schoolId) async {
    try {
      final usersQuery = await firestore
          .collection('users')
          .where('schoolId', isEqualTo: schoolId)
          .get();

      int count = 0;
      final batch = firestore.batch();

      for (final userDoc in usersQuery.docs) {
        final userData = userDoc.data();
        final userId = userDoc.id;

        // Skip parent users - they'll be handled separately
        if (userData['role'] == 'parent') continue;

        // Create user in nested structure
        final newUserRef = firestore
            .collection('schools')
            .doc(schoolId)
            .collection('users')
            .doc(userId);

        batch.set(newUserRef, {
          ...userData,
          'migratedAt': FieldValue.serverTimestamp(),
        });

        count++;

        // Commit batch every 500 operations
        if (count % 500 == 0) {
          await batch.commit();
          print('  ... Migrated $count users');
        }
      }

      await batch.commit();
      print('  ✓ Migrated $count users (staff/admin/teachers)');
    } catch (e) {
      print('  ✗ Failed to migrate users: $e');
      rethrow;
    }
  }

  /// Migrate all students for a specific school
  Future<void> _migrateStudentsForSchool(String schoolId) async {
    try {
      final studentsQuery = await firestore
          .collection('students')
          .where('schoolId', isEqualTo: schoolId)
          .get();

      int count = 0;
      final batch = firestore.batch();

      for (final studentDoc in studentsQuery.docs) {
        final studentData = studentDoc.data();
        final studentId = studentDoc.id;

        // Create student in nested structure
        final newStudentRef = firestore
            .collection('schools')
            .doc(schoolId)
            .collection('students')
            .doc(studentId);

        batch.set(newStudentRef, {
          ...studentData,
          'migratedAt': FieldValue.serverTimestamp(),
        });

        count++;

        if (count % 500 == 0) {
          await batch.commit();
          print('  ... Migrated $count students');
        }
      }

      await batch.commit();
      print('  ✓ Migrated $count students');
    } catch (e) {
      print('  ✗ Failed to migrate students: $e');
      rethrow;
    }
  }

  /// Migrate all classes for a specific school
  Future<void> _migrateClassesForSchool(String schoolId) async {
    try {
      final classesQuery = await firestore
          .collection('classes')
          .where('schoolId', isEqualTo: schoolId)
          .get();

      int count = 0;
      final batch = firestore.batch();

      for (final classDoc in classesQuery.docs) {
        final classData = classDoc.data();
        final classId = classDoc.id;

        // Create class in nested structure
        final newClassRef = firestore
            .collection('schools')
            .doc(schoolId)
            .collection('classes')
            .doc(classId);

        batch.set(newClassRef, {
          ...classData,
          'migratedAt': FieldValue.serverTimestamp(),
        });

        count++;

        if (count % 500 == 0) {
          await batch.commit();
          print('  ... Migrated $count classes');
        }
      }

      await batch.commit();
      print('  ✓ Migrated $count classes');
    } catch (e) {
      print('  ✗ Failed to migrate classes: $e');
      rethrow;
    }
  }

  /// Migrate all reading logs for a specific school
  Future<void> _migrateReadingLogsForSchool(String schoolId) async {
    try {
      // Reading logs don't have schoolId, so we need to get them via student/parent relationships
      final studentsQuery = await firestore
          .collection('students')
          .where('schoolId', isEqualTo: schoolId)
          .get();

      final studentIds = studentsQuery.docs.map((doc) => doc.id).toList();

      if (studentIds.isEmpty) {
        print('  ✓ No reading logs to migrate');
        return;
      }

      int count = 0;
      final batch = firestore.batch();

      // Query reading logs for these students
      // Note: Firestore has a limit of 10 items in 'whereIn' query
      for (var i = 0; i < studentIds.length; i += 10) {
        final chunk = studentIds.skip(i).take(10).toList();

        final logsQuery = await firestore
            .collection('readingLogs')
            .where('studentId', whereIn: chunk)
            .get();

        for (final logDoc in logsQuery.docs) {
          final logData = logDoc.data();
          final logId = logDoc.id;

          // Create reading log in nested structure
          final newLogRef = firestore
              .collection('schools')
              .doc(schoolId)
              .collection('readingLogs')
              .doc(logId);

          batch.set(newLogRef, {
            ...logData,
            'migratedAt': FieldValue.serverTimestamp(),
          });

          count++;

          if (count % 500 == 0) {
            await batch.commit();
            print('  ... Migrated $count reading logs');
          }
        }
      }

      await batch.commit();
      print('  ✓ Migrated $count reading logs');
    } catch (e) {
      print('  ✗ Failed to migrate reading logs: $e');
      rethrow;
    }
  }

  /// Migrate parent users to their respective schools
  Future<void> _migrateParentUsers() async {
    try {
      final parentsQuery = await firestore
          .collection('users')
          .where('role', isEqualTo: 'parent')
          .get();

      int count = 0;
      final batch = firestore.batch();

      for (final parentDoc in parentsQuery.docs) {
        final parentData = parentDoc.data();
        final parentId = parentDoc.id;

        // Find school through linked children
        final linkedChildren =
            parentData['linkedChildren'] as List<dynamic>? ?? [];
        if (linkedChildren.isEmpty) continue;

        // Get the first child's school
        final firstChildDoc = await firestore
            .collection('students')
            .doc(linkedChildren.first)
            .get();

        if (!firstChildDoc.exists) continue;

        final childData = firstChildDoc.data();
        final schoolId = childData?['schoolId'];

        if (schoolId == null) continue;

        // Create parent in nested structure
        final newParentRef = firestore
            .collection('schools')
            .doc(schoolId)
            .collection('parents')
            .doc(parentId);

        batch.set(newParentRef, {
          ...parentData,
          'schoolId': schoolId, // Add schoolId for consistency
          'migratedAt': FieldValue.serverTimestamp(),
        });

        count++;

        if (count % 500 == 0) {
          await batch.commit();
          print('  ... Migrated $count parents');
        }
      }

      await batch.commit();
      print('✓ Migrated $count parent users');
    } catch (e) {
      print('✗ Failed to migrate parent users: $e');
      rethrow;
    }
  }

  /// Verify migration by comparing counts
  Future<void> verifyMigration() async {
    print('\nVerifying migration...');

    try {
      // Get schools
      final schools = await firestore.collection('schools').get();

      for (final schoolDoc in schools.docs) {
        final schoolId = schoolDoc.id;
        print('\nVerifying school: $schoolId');

        // Compare old vs new counts
        final oldUsers = await firestore
            .collection('users')
            .where('schoolId', isEqualTo: schoolId)
            .where('role', isNotEqualTo: 'parent')
            .get();

        final newUsers = await firestore
            .collection('schools')
            .doc(schoolId)
            .collection('users')
            .get();

        print('  Users: Old=${oldUsers.size}, New=${newUsers.size}');

        final oldStudents = await firestore
            .collection('students')
            .where('schoolId', isEqualTo: schoolId)
            .get();

        final newStudents = await firestore
            .collection('schools')
            .doc(schoolId)
            .collection('students')
            .get();

        print('  Students: Old=${oldStudents.size}, New=${newStudents.size}');

        final oldClasses = await firestore
            .collection('classes')
            .where('schoolId', isEqualTo: schoolId)
            .get();

        final newClasses = await firestore
            .collection('schools')
            .doc(schoolId)
            .collection('classes')
            .get();

        print('  Classes: Old=${oldClasses.size}, New=${newClasses.size}');
      }

      print('\n✅ Verification complete!');
    } catch (e) {
      print('❌ Verification failed: $e');
      rethrow;
    }
  }

  /// Clean up old collections after successful migration
  /// WARNING: This will DELETE all data from old collections!
  Future<void> cleanupOldCollections({required bool confirmDelete}) async {
    if (!confirmDelete) {
      print('❌ Cleanup aborted: confirmDelete must be true');
      return;
    }

    print('\n⚠️  WARNING: Deleting old collections...');

    try {
      // Delete in batches to avoid timeout
      await _deleteCollection('users');
      await _deleteCollection('students');
      await _deleteCollection('classes');
      await _deleteCollection('readingLogs');
      await _deleteCollection('allocations');

      print('✅ Old collections cleaned up successfully');
    } catch (e) {
      print('❌ Cleanup failed: $e');
      rethrow;
    }
  }

  Future<void> _deleteCollection(String collectionPath) async {
    print('  Deleting collection: $collectionPath');

    const batchSize = 500;
    var deleted = 0;

    while (true) {
      final snapshot =
          await firestore.collection(collectionPath).limit(batchSize).get();

      if (snapshot.docs.isEmpty) break;

      final batch = firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      deleted += snapshot.docs.length;
      print('    Deleted $deleted documents...');
    }

    print('  ✓ Deleted $deleted documents from $collectionPath');
  }
}
