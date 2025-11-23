import 'package:firebase_core/firebase_core.dart';
import 'package:lumi_reading_tracker/core/services/user_school_index_service.dart';

/// Migration script to backfill the userSchoolIndex for existing users.
///
/// This script should be run ONCE after deploying the new optimization changes.
/// It will create index entries for all existing users to enable fast login lookups.
///
/// Usage:
/// ```
/// dart run scripts/backfill_user_school_index.dart
/// ```
///
/// The script will:
/// 1. Find all schools in the database
/// 2. For each school, find all users and parents
/// 3. Create userSchoolIndex entries for each user/parent
/// 4. Report the total number of entries created
///
/// This is safe to run multiple times - it will update existing entries.

Future<void> main() async {
  print('🚀 Starting User School Index Backfill Migration\n');

  // Initialize Firebase
  await Firebase.initializeApp();

  final indexService = UserSchoolIndexService();

  try {
    print('📊 Analyzing database...');

    final stats = await indexService.backfillAllSchools();

    print('\n✅ Migration Complete!\n');
    print('📈 Statistics:');
    print('   Schools processed: ${stats['schools']}');
    print('   Teachers/Admins indexed: ${stats['users']}');
    print('   Parents indexed: ${stats['parents']}');
    print('   Total entries created: ${stats['total']}\n');

    print('🎉 All users can now enjoy fast login performance!');
    print('   Login reads reduced from O(n) schools to O(1) - just 2-3 reads total.\n');
  } catch (e) {
    print('\n❌ Migration failed: $e\n');
    print('Please check your Firebase configuration and try again.');
    rethrow;
  }
}
