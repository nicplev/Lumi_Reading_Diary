import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TestDataSetup {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Creates a test school and admin account
  /// School: Beaumaris Primary School (BPS)
  /// Admin Email: admin@bps.edu.au
  /// Admin Password: BPSAdmin2024!
  static Future<void> createTestSchool() async {
    try {
      print('🏫 Creating Beaumaris Primary School...');

      // Note: Running without authentication - Firestore rules must allow this for testing

      // 1. Check if school already exists
      final schoolId = 'beaumaris_primary_school';
      final schoolDoc =
          await _firestore.collection('schools').doc(schoolId).get();

      if (schoolDoc.exists) {
        print('⚠️ School already exists. Updating...');
      }

      // Create or update the school document
      await _firestore.collection('schools').doc(schoolId).set({
        'id': schoolId,
        'name': 'Beaumaris Primary School',
        'abbreviation': 'BPS',
        'address': '123 School Street, Beaumaris VIC 3193',
        'phone': '(03) 9589 1234',
        'email': 'info@bps.edu.au',
        'website': 'https://www.bps.edu.au',
        'principalName': 'Dr. Sarah Johnson',
        'totalStudents': 450,
        'totalTeachers': 28,
        'totalClasses': 18,
        'yearLevels': [
          'Prep',
          'Year 1',
          'Year 2',
          'Year 3',
          'Year 4',
          'Year 5',
          'Year 6'
        ],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'isActive': true,
        'settings': {
          'readingGoalMinutes': 20,
          'allowParentRegistration': true,
          'requireTeacherApproval': true,
          'enableNotifications': true,
        },
      });

      print('✅ School created successfully');

      // 2. Create or sign in admin account
      print('👤 Setting up admin account...');

      final adminEmail = 'admin@bps.edu.au';
      final adminPassword = 'BPSAdmin2024!';

      UserCredential? adminCredential;
      String adminUid;

      try {
        // Try to create the admin account
        adminCredential = await _auth.createUserWithEmailAndPassword(
          email: adminEmail,
          password: adminPassword,
        );
        adminUid = adminCredential.user!.uid;
        print('✅ Admin account created successfully');
      } catch (e) {
        // If account exists, sign in instead
        if (e.toString().contains('email-already-in-use')) {
          print('⚠️ Admin account already exists. Signing in...');
          adminCredential = await _auth.signInWithEmailAndPassword(
            email: adminEmail,
            password: adminPassword,
          );
          adminUid = adminCredential.user!.uid;
          print('✅ Signed in to existing admin account');
        } else {
          rethrow;
        }
      }

      // 3. Create or update the admin user document in Firestore
      await _firestore.collection('users').doc(adminUid).set({
        'uid': adminUid,
        'email': adminEmail,
        'fullName': 'School Administrator',
        'displayName': 'School Administrator',
        'firstName': 'Admin',
        'lastName': 'User',
        'role': 'schoolAdmin',
        'schoolId': schoolId,
        'schoolName': 'Beaumaris Primary School',
        'isActive': true,
        'isApproved': true,
        'permissions': {
          'manageTeachers': true,
          'manageStudents': true,
          'manageClasses': true,
          'viewReports': true,
          'manageSchoolSettings': true,
        },
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'lastLogin': FieldValue.serverTimestamp(),
      });

      print('✅ Admin account created successfully');
      print('📧 Admin Email: $adminEmail');
      print('🔑 Admin Password: $adminPassword');

      // 4. Create sample classes
      print('📚 Creating sample classes...');

      final classes = [
        {
          'name': 'Prep A',
          'teacherId': null,
          'yearLevel': 'Prep',
          'studentCount': 25
        },
        {
          'name': 'Prep B',
          'teacherId': null,
          'yearLevel': 'Prep',
          'studentCount': 24
        },
        {
          'name': '1A',
          'teacherId': null,
          'yearLevel': 'Year 1',
          'studentCount': 26
        },
        {
          'name': '1B',
          'teacherId': null,
          'yearLevel': 'Year 1',
          'studentCount': 25
        },
        {
          'name': '2A',
          'teacherId': null,
          'yearLevel': 'Year 2',
          'studentCount': 27
        },
        {
          'name': '2B',
          'teacherId': null,
          'yearLevel': 'Year 2',
          'studentCount': 26
        },
        {
          'name': '3A',
          'teacherId': null,
          'yearLevel': 'Year 3',
          'studentCount': 28
        },
        {
          'name': '3B',
          'teacherId': null,
          'yearLevel': 'Year 3',
          'studentCount': 27
        },
      ];

      for (var classData in classes) {
        final classDoc = await _firestore.collection('classes').add({
          'schoolId': schoolId,
          'name': classData['name'] as String,
          'yearLevel': classData['yearLevel'],
          'teacherId': classData['teacherId'],
          'studentIds': [],
          'isActive': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        print('  ✅ Created class: ${classData['name']} (ID: ${classDoc.id})');
      }

      // 5. Create sample teachers (they can register later with these emails)
      print('👩‍🏫 Sample teacher accounts to be created:');
      final teacherEmails = [
        'jane.smith@bps.edu.au - Prep A Teacher',
        'john.doe@bps.edu.au - Year 1A Teacher',
        'mary.wilson@bps.edu.au - Year 2A Teacher',
        'robert.brown@bps.edu.au - Year 3A Teacher',
      ];

      for (var teacher in teacherEmails) {
        print('  📧 $teacher');
      }

      print('\n✅ ✅ ✅ Test school setup complete! ✅ ✅ ✅');
      print('\n📋 Summary:');
      print('🏫 School: Beaumaris Primary School (BPS)');
      print('👤 Admin Login:');
      print('   Email: admin@bps.edu.au');
      print('   Password: BPSAdmin2024!');
      print('📚 8 Classes created (Prep to Year 3)');
      print('\n💡 Next steps:');
      print('1. Login with admin account');
      print('2. Create teacher accounts');
      print('3. Assign teachers to classes');
      print('4. Parents can register and link to students');
    } catch (e) {
      print('❌ Error creating test data: $e');
      rethrow;
    }
  }

  /// Deletes all test data (use with caution!)
  static Future<void> deleteTestData() async {
    try {
      print('🗑️ Deleting test data...');

      // Delete school
      await _firestore
          .collection('schools')
          .doc('beaumaris_primary_school')
          .delete();

      // Delete classes
      final classes = await _firestore
          .collection('classes')
          .where('schoolId', isEqualTo: 'beaumaris_primary_school')
          .get();

      for (var doc in classes.docs) {
        await doc.reference.delete();
      }

      // Delete admin user
      final users = await _firestore
          .collection('users')
          .where('schoolId', isEqualTo: 'beaumaris_primary_school')
          .get();

      for (var doc in users.docs) {
        await doc.reference.delete();
      }

      print('✅ Test data deleted successfully');
    } catch (e) {
      print('❌ Error deleting test data: $e');
    }
  }
}

// To use this, call from a button or on app start (for testing only):
// await TestDataSetup.createTestSchool();
