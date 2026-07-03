import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';

class TestDataSetup {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Creates a NEW school admin account for Beaumaris Primary School
  /// Accepts custom email/password so you can use a real verifiable email.
  static Future<void> createNewSchoolAdmin({
    required String email,
    required String password,
  }) async {
    try {
      print('Creating new school admin account...');

      const schoolId = 'beaumaris_primary_school';
      final adminEmail = email.trim().toLowerCase();
      final adminPassword = password;

      // Create the Firebase Auth account
      UserCredential adminCredential;
      String adminUid;

      try {
        adminCredential = await _auth.createUserWithEmailAndPassword(
          email: adminEmail,
          password: adminPassword,
        );
        adminUid = adminCredential.user!.uid;
        print('Auth account created: $adminUid');
      } catch (e) {
        if (e.toString().contains('email-already-in-use')) {
          // Already exists — try to sign in to get UID
          print('Account already exists, signing in...');
          try {
            adminCredential = await _auth.signInWithEmailAndPassword(
              email: adminEmail,
              password: adminPassword,
            );
            adminUid = adminCredential.user!.uid;
            print('Signed in to existing account: $adminUid');
          } catch (_) {
            throw Exception(
              'An account with this email already exists but the password does not match. '
              'Use the correct password for the existing account, or try a different email.',
            );
          }
        } else {
          rethrow;
        }
      }

      // Create Firestore user document in the school's users subcollection
      // (login screen searches schools/{schoolId}/users/{uid})
      final now = FieldValue.serverTimestamp();
      final userData = {
        'uid': adminUid,
        'email': adminEmail,
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
        'createdAt': now,
        'updatedAt': now,
        'lastLogin': now,
        'lastLoginAt': now,
      };

      // Write to school subcollection (where login screen looks)
      await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('users')
          .doc(adminUid)
          .set(userData);

      // Also write to top-level users collection (for splash screen / userProvider)
      await _firestore.collection('users').doc(adminUid).set(userData);

      // Create email-to-school index entry (for fast login lookup)
      final emailHash = sha256.convert(utf8.encode(adminEmail.toLowerCase().trim())).toString();
      await _firestore.collection('userSchoolIndex').doc(emailHash).set({
        'email': adminEmail,
        'schoolId': schoolId,
        'userType': 'user',
        'userId': adminUid,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('Firestore user document created');

      // Send verification email before signing out
      if (_auth.currentUser != null && !_auth.currentUser!.emailVerified) {
        await _auth.currentUser!.sendEmailVerification();
        print('Verification email sent to $adminEmail');
      }

      print('');
      print('=== NEW ADMIN ACCOUNT ===');
      print('Email:    $adminEmail');
      print('Password: $adminPassword');
      print('School:   Beaumaris Primary School');
      print('UID:      $adminUid');
      print('=========================');

      // Sign out so the user can log in manually from the login screen
      await _auth.signOut();
      print('Signed out. Verify your email, then log in.');
    } catch (e) {
      print('Error creating admin: $e');
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
