/// Backfill onboarding records to align status/currentStep/completedSteps fields.
///
/// Usage:
///   dart run scripts/backfill_onboarding_fields.dart
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

const _orderedSteps = <String>[
  'schoolInfo',
  'adminAccount',
  'readingLevels',
  'importData',
  'inviteTeachers',
  'completed',
];

Future<void> main() async {
  await Firebase.initializeApp();
  final firestore = FirebaseFirestore.instance;

  print('Starting onboarding fields backfill...');

  final snapshot = await firestore.collection('schoolOnboarding').get();
  print('Loaded ${snapshot.docs.length} onboarding documents');

  WriteBatch batch = firestore.batch();
  var pendingWrites = 0;
  var updatedCount = 0;

  for (final doc in snapshot.docs) {
    final data = doc.data();
    final status = (data['status'] as String?) ?? 'demo';
    final currentStep = (data['currentStep'] as String?) ?? 'schoolInfo';
    final completedSteps =
        List<String>.from(data['completedSteps'] as List<dynamic>? ?? const []);

    final update = <String, dynamic>{};

    // Ensure step progression is monotonic up to current step.
    final currentIndex = _orderedSteps.indexOf(currentStep);
    if (currentIndex >= 0) {
      for (var i = 0; i <= currentIndex; i++) {
        if (!completedSteps.contains(_orderedSteps[i])) {
          completedSteps.add(_orderedSteps[i]);
        }
      }
    }

    if (status == 'active') {
      if (!completedSteps.contains('completed')) {
        completedSteps.add('completed');
      }
      if (currentStep != 'completed') {
        update['currentStep'] = 'completed';
      }
      if (data['registrationCompletedAt'] == null) {
        update['registrationCompletedAt'] = FieldValue.serverTimestamp();
      }
    }

    if (status == 'registered' || status == 'setupInProgress') {
      if (!completedSteps.contains('schoolInfo')) {
        completedSteps.add('schoolInfo');
      }
      if (!completedSteps.contains('adminAccount')) {
        completedSteps.add('adminAccount');
      }
    }

    update['completedSteps'] = completedSteps;
    update['lastUpdatedAt'] = FieldValue.serverTimestamp();

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
