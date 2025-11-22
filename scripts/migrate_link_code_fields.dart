/// Migration script to fix field names in studentLinkCodes collection
/// This ensures all documents use 'expiresAt' instead of 'expiryDate'
/// Run this script before deploying the cloud function fix
///
/// Usage:
/// dart run scripts/migrate_link_code_fields.dart
///
/// Make sure you have configured Firebase credentials before running:
/// export GOOGLE_APPLICATION_CREDENTIALS="path/to/service-account-key.json"

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

Future<void> main() async {
  print('🔄 Starting link code field migration...\n');

  try {
    // Initialize Firebase
    await Firebase.initializeApp();
    final firestore = FirebaseFirestore.instance;

    // Get all link codes
    print('📦 Fetching all link code documents...');
    final snapshot = await firestore.collection('studentLinkCodes').get();

    print('Found ${snapshot.docs.length} documents\n');

    if (snapshot.docs.isEmpty) {
      print('✅ No documents to migrate. Migration complete!');
      return;
    }

    final batch = firestore.batch();
    int migratedCount = 0;
    int alreadyCorrectCount = 0;
    int batchCount = 0;

    for (final doc in snapshot.docs) {
      final data = doc.data();

      // Check if old field exists and new field doesn't
      if (data.containsKey('expiryDate') && !data.containsKey('expiresAt')) {
        // Migrate the field
        batch.update(doc.reference, {
          'expiresAt': data['expiryDate'],
        });

        migratedCount++;
        print(
            '  ➡️  Migrating document ${doc.id}: expiryDate -> expiresAt (${data['code']})');

        // Commit every 500 documents (Firestore batch limit)
        if (migratedCount > 0 && migratedCount % 500 == 0) {
          print('\n⚡ Committing batch ${++batchCount}...');
          await batch.commit();
          print('✅ Batch $batchCount committed successfully\n');
        }
      } else if (data.containsKey('expiresAt')) {
        alreadyCorrectCount++;
      } else {
        print(
            '  ⚠️  Warning: Document ${doc.id} has neither expiryDate nor expiresAt');
      }
    }

    // Commit remaining documents
    if (migratedCount % 500 != 0) {
      print('\n⚡ Committing final batch...');
      await batch.commit();
      print('✅ Final batch committed successfully\n');
    }

    // Print summary
    print('━' * 50);
    print('📊 Migration Summary:');
    print('━' * 50);
    print('  Total documents scanned: ${snapshot.docs.length}');
    print('  Documents migrated: $migratedCount');
    print('  Documents already correct: $alreadyCorrectCount');
    print('  Documents with issues: ${snapshot.docs.length - migratedCount - alreadyCorrectCount}');
    print('━' * 50);
    print('\n✅ Migration complete!');

    if (migratedCount > 0) {
      print(
          '\n💡 Next steps:');
      print('   1. Deploy the updated cloud function');
      print('   2. Monitor the cleanup function logs');
      print('   3. Verify expired codes are being cleaned up');
    }
  } catch (error) {
    print('\n❌ Migration failed with error:');
    print(error);
    print('\nPlease check:');
    print('  - Firebase credentials are configured');
    print('  - You have write access to the studentLinkCodes collection');
    print('  - Network connectivity is available');
    rethrow;
  }
}
