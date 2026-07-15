import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/services/account_deletion_service.dart';

class _Invoker {
  final calls = <String, List<Map<String, dynamic>>>{};
  Object? response;
  Object? error;

  Future<Object?> call(String name, Map<String, dynamic> arguments) async {
    calls.putIfAbsent(name, () => []).add(arguments);
    if (error != null) throw error!;
    return response;
  }
}

void main() {
  test('account deletion sends only the fixed typed confirmation', () async {
    final invoker = _Invoker()
      ..response = {
        'jobId': 'account_hash',
        'kind': 'account',
        'status': 'completed',
        'attemptCount': 1,
        'retrying': false,
      };
    final service = AccountDeletionService(callableInvoker: invoker.call);

    final result = await service.requestAccountDeletion();

    expect(result.state, DeletionState.completed);
    expect(invoker.calls['requestAccountDeletion'], [
      {'confirmation': 'DELETE'}
    ]);
  });

  test('student deletion sends the authoritative identifiers and name', () async {
    final invoker = _Invoker()
      ..response = {
        'jobId': 'student_hash',
        'kind': 'student',
        'status': 'processing',
        'attemptCount': 1,
        'retrying': false,
      };
    final service = AccountDeletionService(callableInvoker: invoker.call);

    final result = await service.requestStudentDeletion(
      schoolId: 'school_1',
      studentId: 'student_1',
      studentName: 'Ari Reader',
    );

    expect(result.kind, DeletionKind.student);
    expect(invoker.calls['requestStudentDeletion'], [
      {
        'schoolId': 'school_1',
        'studentId': 'student_1',
        'studentName': 'Ari Reader',
        'confirmation': 'DELETE',
      }
    ]);
  });

  test('status response supports no existing job', () async {
    final invoker = _Invoker()..response = {'job': null};
    final service = AccountDeletionService(callableInvoker: invoker.call);

    expect(await service.loadAccountStatus(), isNull);
    expect(invoker.calls['getMyDeletionStatus'], [
      {'kind': 'account'}
    ]);
  });

  test('recent-login-required remains identifiable for the UI', () async {
    final invoker = _Invoker()
      ..error = FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'recent-login-required',
      );
    final service = AccountDeletionService(callableInvoker: invoker.call);

    await expectLater(
      service.requestAccountDeletion(),
      throwsA(isA<AccountDeletionException>().having(
        (error) => error.requiresRecentLogin,
        'requiresRecentLogin',
        true,
      )),
    );
  });
}
