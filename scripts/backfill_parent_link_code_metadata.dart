/// Backfill metadata and lifecycle fields for studentLinkCodes documents.
///
/// Usage:
///   dart run scripts/backfill_parent_link_code_metadata.dart
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

Future<void> main() async {
  await Firebase.initializeApp();
  final firestore = FirebaseFirestore.instance;

  print('Starting parent link code metadata backfill...');

  final snapshot = await firestore.collection('studentLinkCodes').get();
  print('Loaded ${snapshot.docs.length} link code documents');

  WriteBatch batch = firestore.batch();
  var pendingWrites = 0;
  var updatedCount = 0;

  for (final doc in snapshot.docs) {
    final data = doc.data();
    final schoolId = data['schoolId'] as String?;
    final studentId = data['studentId'] as String?;

    if (schoolId == null ||
        schoolId.isEmpty ||
        studentId == null ||
        studentId.isEmpty) {
      continue;
    }

    final update = <String, dynamic>{};

    // Legacy expiryDate -> expiresAt.
    if (!data.containsKey('expiresAt') && data['expiryDate'] != null) {
      update['expiresAt'] = data['expiryDate'];
    }

    final metadata = Map<String, dynamic>.from(data['metadata'] as Map? ?? {});

    final needsStudentMetadata = metadata['studentFullName'] == null ||
        metadata['studentFirstName'] == null ||
        metadata['studentLastName'] == null ||
        metadata['studentId'] == null ||
        metadata['classId'] == null ||
        metadata['className'] == null;

    if (needsStudentMetadata) {
      final studentDoc = await firestore
          .collection('schools')
          .doc(schoolId)
          .collection('students')
          .doc(studentId)
          .get();

      if (studentDoc.exists) {
        final student = studentDoc.data()!;
        final firstName = (student['firstName'] as String?) ?? '';
        final lastName = (student['lastName'] as String?) ?? '';
        final classId = (student['classId'] as String?) ?? '';

        String className = '';
        if (classId.isNotEmpty) {
          final classDoc = await firestore
              .collection('schools')
              .doc(schoolId)
              .collection('classes')
              .doc(classId)
              .get();
          className = (classDoc.data()?['name'] as String?) ?? '';
        }

        metadata['studentFirstName'] = firstName;
        metadata['studentLastName'] = lastName;
        metadata['studentFullName'] = '$firstName $lastName'.trim();
        metadata['studentId'] = student['studentId'] ?? studentId;
        metadata['classId'] = classId;
        metadata['className'] = className;
      }
    }

    if (metadata.isNotEmpty) {
      update['metadata'] = metadata;
    }

    if (update.isNotEmpty) {
      batch.update(doc.reference, update);
      pendingWrites++;
      updatedCount++;
    }

    if (pendingWrites >= 400) {
      await batch.commit();
      batch = firestore.batch();
      pendingWrites = 0;
      print('Committed 400 updates...');
    }
  }

  if (pendingWrites > 0) {
    await batch.commit();
  }

  print('Backfill complete. Updated $updatedCount documents.');
}
