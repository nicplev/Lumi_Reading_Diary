import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:lumi_reading_tracker/firebase_options.dart';

/// Seeds the `_meta/healthcheck` document the in-app ServiceStatus L3
/// probe reads every ~30s. Without this doc every probe returns
/// `firebaseDown` and the banner will be wrong for everyone.
///
/// Idempotent — safe to run multiple times. Bumps `version` on each run
/// so you can confirm by reading the doc.
///
/// Usage:
///   dart run scripts/seed_healthcheck.dart
///
/// The script honours the same `DefaultFirebaseOptions.currentPlatform`
/// the app uses, so it points at whichever project that file resolves
/// (dev vs prod is selected at build/run time the same way as the app).
Future<void> main() async {
  // ignore: avoid_print
  print('Seeding _meta/healthcheck…');

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final doc = FirebaseFirestore.instance.doc('_meta/healthcheck');
  final existing = await doc.get();
  final prevVersion = (existing.data()?['version'] as num?)?.toInt() ?? 0;

  await doc.set({
    'version': prevVersion + 1,
    'updatedAt': FieldValue.serverTimestamp(),
    'note':
        'L3 probe target for ServiceStatusController — see lib/core/services/'
            'service_status_controller.dart',
  });

  // ignore: avoid_print
  print('Done. version=${prevVersion + 1}. '
      'Probe will report Firebase reachable on next probe.');
}
