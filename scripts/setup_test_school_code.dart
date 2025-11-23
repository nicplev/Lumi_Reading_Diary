import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Helper script to create the test school code for Beaumaris Primary School.
///
/// This script automates the setup described in SCHOOL_CODE_SETUP.md
///
/// Usage:
/// ```
/// dart run scripts/setup_test_school_code.dart
/// ```

void main() async {
  print('🚀 Setting up test school code for Beaumaris Primary School...\n');

  try {
    // Initialize Firebase
    await Firebase.initializeApp();
    final firestore = FirebaseFirestore.instance;

    // Step 1: Find Beaumaris Primary School
    print('📍 Step 1: Finding Beaumaris Primary School...');

    final schoolsQuery = await firestore
        .collection('schools')
        .where('name', isEqualTo: 'Beaumaris Primary School')
        .limit(1)
        .get();

    if (schoolsQuery.docs.isEmpty) {
      print('❌ Error: Beaumaris Primary School not found in Firestore');
      print('   Please ensure the school exists in the schools collection');
      print('   with name: "Beaumaris Primary School"');
      return;
    }

    final schoolDoc = schoolsQuery.docs.first;
    final schoolId = schoolDoc.id;
    final schoolData = schoolDoc.data();
    final schoolName = schoolData['name'] as String;

    print('✅ Found school:');
    print('   - School ID: $schoolId');
    print('   - School Name: $schoolName\n');

    // Step 2: Check if code already exists
    print('📍 Step 2: Checking if test code already exists...');

    final existingCodeQuery = await firestore
        .collection('schoolCodes')
        .where('code', isEqualTo: 'BPS74383')
        .limit(1)
        .get();

    if (existingCodeQuery.docs.isNotEmpty) {
      print('⚠️  School code BPS74383 already exists!');
      print('   Document ID: ${existingCodeQuery.docs.first.id}');
      print('   Would you like to delete and recreate it? (You can do this manually in Firebase Console)');
      return;
    }

    print('✅ Code BPS74383 does not exist yet\n');

    // Step 3: Create the school code
    print('📍 Step 3: Creating school code BPS74383...');

    final codeData = {
      'code': 'BPS74383',
      'schoolId': schoolId,
      'schoolName': schoolName,
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': 'test_setup_script',
      'usageCount': 0,
      'maxUsages': null,
      'expiresAt': null,
    };

    final codeRef = await firestore.collection('schoolCodes').add(codeData);

    print('✅ School code created successfully!');
    print('   - Document ID: ${codeRef.id}');
    print('   - Code: BPS74383');
    print('   - School: $schoolName');
    print('   - School ID: $schoolId\n');

    // Step 4: Verification
    print('📍 Step 4: Verifying the code...');

    final verifyQuery = await firestore
        .collection('schoolCodes')
        .where('code', isEqualTo: 'BPS74383')
        .limit(1)
        .get();

    if (verifyQuery.docs.isNotEmpty) {
      final verifiedCode = verifyQuery.docs.first.data();
      print('✅ Verification successful!');
      print('   Code details:');
      print('   - code: ${verifiedCode['code']}');
      print('   - schoolId: ${verifiedCode['schoolId']}');
      print('   - schoolName: ${verifiedCode['schoolName']}');
      print('   - isActive: ${verifiedCode['isActive']}');
      print('   - usageCount: ${verifiedCode['usageCount']}\n');
    }

    print('🎉 Setup complete!');
    print('\nNext steps:');
    print('1. Run: flutter run');
    print('2. Navigate to registration screen');
    print('3. Select "Teacher" role');
    print('4. Enter school code: BPS74383');
    print('5. Complete registration');
    print('\nSee SCHOOL_CODE_SETUP.md for detailed testing instructions.');

  } catch (e) {
    print('❌ Error during setup: $e');
    print('\nTroubleshooting:');
    print('1. Ensure Firebase is properly configured');
    print('2. Check that firebase_core is initialized');
    print('3. Verify Firestore rules allow write access to schoolCodes collection');
  }
}
