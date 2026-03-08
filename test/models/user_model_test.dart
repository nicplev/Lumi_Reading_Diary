import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:lumi_reading_tracker/data/models/user_model.dart';

void main() {
  group('UserModel', () {
    group('fromFirestore / toFirestore roundtrip', () {
      test('serializes and deserializes parent user correctly', () async {
        final firestore = FakeFirebaseFirestore();
        final original = UserModel(
          id: 'user-1',
          email: 'parent@test.com',
          fullName: 'Jane Doe',
          role: UserRole.parent,
          schoolId: 'school-1',
          linkedChildren: ['child-1', 'child-2'],
          createdAt: DateTime(2026, 1, 15),
        );

        await firestore
            .collection('users')
            .doc(original.id)
            .set(original.toFirestore());

        final doc =
            await firestore.collection('users').doc(original.id).get();
        final restored = UserModel.fromFirestore(doc);

        expect(restored.id, original.id);
        expect(restored.email, original.email);
        expect(restored.fullName, original.fullName);
        expect(restored.role, UserRole.parent);
        expect(restored.schoolId, original.schoolId);
        expect(restored.linkedChildren, ['child-1', 'child-2']);
        expect(restored.isActive, true);
      });

      test('serializes and deserializes teacher user correctly', () async {
        final firestore = FakeFirebaseFirestore();
        final original = UserModel(
          id: 'teacher-1',
          email: 'teacher@test.com',
          fullName: 'Mr. Smith',
          role: UserRole.teacher,
          schoolId: 'school-1',
          classIds: ['class-a', 'class-b'],
          createdAt: DateTime(2026, 1, 15),
        );

        await firestore
            .collection('users')
            .doc(original.id)
            .set(original.toFirestore());

        final doc =
            await firestore.collection('users').doc(original.id).get();
        final restored = UserModel.fromFirestore(doc);

        expect(restored.role, UserRole.teacher);
        expect(restored.classIds, ['class-a', 'class-b']);
      });

      test('serializes and deserializes admin user correctly', () async {
        final firestore = FakeFirebaseFirestore();
        final original = UserModel(
          id: 'admin-1',
          email: 'admin@test.com',
          fullName: 'Admin User',
          role: UserRole.schoolAdmin,
          schoolId: 'school-1',
          createdAt: DateTime(2026, 1, 15),
        );

        await firestore
            .collection('users')
            .doc(original.id)
            .set(original.toFirestore());

        final doc =
            await firestore.collection('users').doc(original.id).get();
        final restored = UserModel.fromFirestore(doc);

        expect(restored.role, UserRole.schoolAdmin);
      });
    });

    group('UserRole enum', () {
      test('has three roles', () {
        expect(UserRole.values.length, 3);
        expect(UserRole.values, contains(UserRole.parent));
        expect(UserRole.values, contains(UserRole.teacher));
        expect(UserRole.values, contains(UserRole.schoolAdmin));
      });
    });

    group('copyWith', () {
      test('creates copy with updated fields', () {
        final user = UserModel(
          id: 'user-1',
          email: 'old@test.com',
          fullName: 'Old Name',
          role: UserRole.parent,
          createdAt: DateTime(2026, 1, 15),
        );

        final updated = user.copyWith(
          email: 'new@test.com',
          fullName: 'New Name',
        );

        expect(updated.email, 'new@test.com');
        expect(updated.fullName, 'New Name');
        expect(updated.id, user.id);
        expect(updated.role, user.role);
      });

      test('preserves original when no fields specified', () {
        final user = UserModel(
          id: 'user-1',
          email: 'test@test.com',
          fullName: 'Test',
          role: UserRole.teacher,
          schoolId: 'school-1',
          classIds: ['class-1'],
          createdAt: DateTime(2026, 1, 15),
        );

        final copy = user.copyWith();

        expect(copy.id, user.id);
        expect(copy.email, user.email);
        expect(copy.fullName, user.fullName);
        expect(copy.role, user.role);
        expect(copy.schoolId, user.schoolId);
        expect(copy.classIds, user.classIds);
      });
    });

    group('defaults', () {
      test('has sensible defaults for optional fields', () {
        final user = UserModel(
          id: 'user-1',
          email: 'test@test.com',
          fullName: 'Test',
          role: UserRole.parent,
          createdAt: DateTime(2026, 1, 15),
        );

        expect(user.linkedChildren, isEmpty);
        expect(user.classIds, isEmpty);
        expect(user.profileImageUrl, isNull);
        expect(user.isActive, true);
        expect(user.lastLoginAt, isNull);
        expect(user.preferences, isNull);
        expect(user.fcmToken, isNull);
        expect(user.schoolId, isNull);
      });
    });

    group('fromFirestore edge cases', () {
      test('handles missing fields gracefully', () async {
        final firestore = FakeFirebaseFirestore();

        await firestore.collection('users').doc('incomplete').set({
          'email': 'test@test.com',
        });

        final doc =
            await firestore.collection('users').doc('incomplete').get();
        final user = UserModel.fromFirestore(doc);

        expect(user.id, 'incomplete');
        expect(user.email, 'test@test.com');
        expect(user.fullName, '');
        expect(user.role, UserRole.parent);
        expect(user.linkedChildren, isEmpty);
      });
    });
  });
}
