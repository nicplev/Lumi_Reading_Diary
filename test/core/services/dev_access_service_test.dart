import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/core/services/dev_access_service.dart';

void main() {
  test('checks only the authenticated caller through the server callable',
      () async {
    final auth = MockFirebaseAuth(
      mockUser: MockUser(
        uid: 'dev_1',
        email: 'developer@example.test',
        isEmailVerified: true,
      ),
      signedIn: true,
    );
    final calls = <(String, Map<String, dynamic>)>[];
    final service = DevAccessService.debug(
      auth: auth,
      callableInvoker: (name, data) async {
        calls.add((name, data));
        return {'hasAccess': true};
      },
    );
    addTearDown(service.dispose);

    await service.refresh();

    expect(service.hasAccess, isTrue);
    expect(calls, isNotEmpty);
    expect(calls.last.$1, 'checkDevAccess');
    expect(calls.last.$2, isEmpty);
  });

  test('fails closed when the callable errors', () async {
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'dev_1', email: 'developer@example.test'),
      signedIn: true,
    );
    final service = DevAccessService.debug(
      auth: auth,
      callableInvoker: (_, __) async => throw StateError('unavailable'),
    );
    addTearDown(service.dispose);

    await service.refresh();

    expect(service.hasAccess, isFalse);
  });
}
