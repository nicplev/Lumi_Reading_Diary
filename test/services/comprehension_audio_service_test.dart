import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/services/comprehension_audio_service.dart';

class _Invoker {
  final calls = <String, List<Map<String, dynamic>>>{};
  final limitedUseAppCheck = <String, List<bool>>{};
  Object? response;

  Future<Object?> call(
    String name,
    Map<String, dynamic> arguments, {
    required bool limitedUseAppCheckToken,
  }) async {
    calls.putIfAbsent(name, () => []).add(arguments);
    limitedUseAppCheck.putIfAbsent(name, () => []).add(limitedUseAppCheckToken);
    return response;
  }
}

void main() {
  test('confirm upload calls the server receipt function', () async {
    final invoker = _Invoker()..response = {'confirmed': true};
    final service = ComprehensionAudioService(invoker: invoker.call);

    await service.confirmUpload(
      schoolId: 'school_x',
      logId: 'log_x',
      durationSec: 12,
    );

    expect(invoker.calls['confirmComprehensionAudioUpload'], [
      {'schoolId': 'school_x', 'logId': 'log_x', 'durationSec': 12}
    ]);
    expect(
        invoker.limitedUseAppCheck['confirmComprehensionAudioUpload'], [true]);
  });

  test('delete audio returns the server idempotency result', () async {
    final invoker = _Invoker()
      ..response = {'deleted': false, 'reason': 'no_audio'};
    final service = ComprehensionAudioService(invoker: invoker.call);

    expect(
      await service.deleteAudio(schoolId: 'school_x', logId: 'log_x'),
      isFalse,
    );
    expect(invoker.calls['deleteComprehensionAudio'], [
      {'schoolId': 'school_x', 'logId': 'log_x'}
    ]);
    expect(invoker.limitedUseAppCheck['deleteComprehensionAudio'], [true]);
  });

  test('playback URL and lifetime are parsed from the callable', () async {
    final invoker = _Invoker()
      ..response = {'url': 'https://signed.example/audio', 'expiresInSec': 900};
    final service = ComprehensionAudioService(invoker: invoker.call);

    final result = await service.getAudioUrl(
      schoolId: 'school_x',
      logId: 'log_x',
    );

    expect(result.url, 'https://signed.example/audio');
    expect(result.expiresInSec, 900);
    expect(invoker.calls['getComprehensionAudioUrl'], [
      {'schoolId': 'school_x', 'logId': 'log_x'}
    ]);
    expect(invoker.limitedUseAppCheck['getComprehensionAudioUrl'], [true]);
  });

  test('invalid playback response fails closed', () async {
    final invoker = _Invoker()..response = {'url': ''};
    final service = ComprehensionAudioService(invoker: invoker.call);

    await expectLater(
      service.getAudioUrl(schoolId: 'school_x', logId: 'log_x'),
      throwsStateError,
    );
  });
}
