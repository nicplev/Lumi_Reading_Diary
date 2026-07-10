import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/data/models/student_model.dart';
import 'package:lumi_reading_tracker/data/models/user_model.dart';
import 'package:lumi_reading_tracker/data/providers/active_child_provider.dart';
import 'package:lumi_reading_tracker/data/providers/user_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const schoolId = 'school_1';
  const parentId = 'parent_1';

  UserModel parentUser() => UserModel(
        id: parentId,
        email: 'parent@example.com',
        fullName: 'Pat Parent',
        role: UserRole.parent,
        schoolId: schoolId,
        createdAt: DateTime(2024, 1, 1),
      );

  late FakeFirebaseFirestore firestore;

  Future<void> seedStudent(String id, String firstName) {
    return firestore
        .collection('schools')
        .doc(schoolId)
        .collection('students')
        .doc(id)
        .set({
      'firstName': firstName,
      'lastName': 'Kid',
      'schoolId': schoolId,
      'classId': 'class_1',
      'parentIds': [parentId],
      'isActive': true,
      'access': {
        'status': 'active',
        'academicYear': 2026,
        'expiresAt': Timestamp.fromDate(DateTime(2027, 1, 31)),
      },
      'createdAt': Timestamp.now(),
    });
  }

  Future<void> setLinkedChildren(List<String> ids) {
    return firestore
        .collection('schools')
        .doc(schoolId)
        .collection('parents')
        .doc(parentId)
        .set({'linkedChildren': ids}, SetOptions(merge: true));
  }

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        firestoreProvider.overrideWithValue(firestore),
        userProvider.overrideWith(
          (ref) => Stream<UserModel?>.value(parentUser()),
        ),
      ],
    );
    addTearDown(container.dispose);
    // Keep the stream provider subscribed for the test's lifetime.
    container.listen(parentChildrenProvider, (_, __) {});
    return container;
  }

  /// Polls [parentChildrenProvider] until [test] passes, then returns the list.
  Future<List<StudentModel>> readChildrenWhen(
    ProviderContainer container,
    bool Function(List<StudentModel>) test,
  ) async {
    for (var i = 0; i < 200; i++) {
      final value = container.read(parentChildrenProvider).value;
      if (value != null && test(value)) return value;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('parentChildrenProvider never satisfied the expected condition');
  }

  setUp(() {
    firestore = FakeFirebaseFirestore();
    SharedPreferences.setMockInitialValues({});
  });

  test('parentChildrenProvider reflects a newly linked child reactively',
      () async {
    await seedStudent('child_1', 'Mia');
    await seedStudent('child_2', 'Leo');
    await setLinkedChildren(['child_1']);

    final container = makeContainer();

    final initial = await readChildrenWhen(container, (l) => l.isNotEmpty);
    expect(initial.map((c) => c.id).toList(), ['child_1']);

    // Link a second child — the streamed parent doc must push the update.
    await setLinkedChildren(['child_1', 'child_2']);

    final updated = await readChildrenWhen(container, (l) => l.length == 2);
    expect(updated.map((c) => c.id).toList(), ['child_1', 'child_2']);
    expect(updated.map((c) => c.firstName).toList(), ['Mia', 'Leo']);
  });

  test('activeChildProvider defaults to first child and follows select()',
      () async {
    await seedStudent('child_1', 'Mia');
    await seedStudent('child_2', 'Leo');
    await setLinkedChildren(['child_1', 'child_2']);

    final container = makeContainer();
    await readChildrenWhen(container, (l) => l.length == 2);

    // No stored selection → resolves to the first child.
    expect(container.read(activeChildProvider).value?.id, 'child_1');

    // Selecting a child updates the resolved active child.
    await container.read(activeChildIdProvider.notifier).select('child_2');
    expect(container.read(activeChildProvider).value?.id, 'child_2');

    // A stale / unknown id falls back to the first child.
    await container.read(activeChildIdProvider.notifier).select('ghost');
    expect(container.read(activeChildProvider).value?.id, 'child_1');
  });

  test('student access and archive changes propagate without relinking',
      () async {
    await seedStudent('child_1', 'Mia');
    await setLinkedChildren(['child_1']);
    final container = makeContainer();

    final initial = await readChildrenWhen(
      container,
      (children) =>
          children.length == 1 && children.single.access?.status == 'active',
    );
    expect(initial.single.hasActiveAccess, isTrue);

    final studentRef = firestore
        .collection('schools')
        .doc(schoolId)
        .collection('students')
        .doc('child_1');
    await studentRef.update({'access.status': StudentAccess.statusRevoked});

    final revoked = await readChildrenWhen(
      container,
      (children) =>
          children.length == 1 &&
          children.single.access?.status == StudentAccess.statusRevoked,
    );
    // Revocation blocks logging but deliberately keeps the guardian link and
    // child visible, so the app can explain the access state.
    expect(revoked.single.hasActiveAccess, isFalse);

    await studentRef.update({'isActive': false});
    final archived =
        await readChildrenWhen(container, (children) => children.isEmpty);
    expect(archived, isEmpty);
  });
}
