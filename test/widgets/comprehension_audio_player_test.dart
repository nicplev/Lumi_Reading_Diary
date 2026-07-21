import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/core/widgets/audio/comprehension_audio_player.dart';
import 'package:lumi_reading_tracker/services/comprehension_audio_service.dart';

void main() {
  test('review threshold is reached at 80 percent, not before', () {
    expect(
      ComprehensionAudioPlayer.hasReachedReviewThreshold(
        position: const Duration(seconds: 79),
        total: const Duration(seconds: 100),
      ),
      isFalse,
    );
    expect(
      ComprehensionAudioPlayer.hasReachedReviewThreshold(
        position: const Duration(seconds: 80),
        total: const Duration(seconds: 100),
      ),
      isTrue,
    );
  });

  testWidgets('does not request a signed URL before the teacher presses play',
      (tester) async {
    var calls = 0;
    final service = ComprehensionAudioService(
      invoker: (name, args, {required limitedUseAppCheckToken}) async {
        calls++;
        return {
          'url': 'https://example.invalid/audio',
          'expiresInSec': 900,
        };
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComprehensionAudioPlayer(
            storagePath: 'schools/school_x/comprehension_audio/log_x.m4a',
            schoolId: 'school_x',
            logId: 'log_x',
            durationSec: 4,
            audioService: service,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(calls, 0);
    expect(find.byIcon(Icons.play_circle_fill), findsOneWidget);
  });

  testWidgets('successful delete removes the player without a host callback',
      (tester) async {
    var deleteCalls = 0;
    bool? usedLimitedToken;
    final service = ComprehensionAudioService(
      invoker: (name, args, {required limitedUseAppCheckToken}) async {
        if (name == 'deleteComprehensionAudio') {
          deleteCalls++;
          usedLimitedToken = limitedUseAppCheckToken;
          return {'deleted': true};
        }
        throw StateError('Unexpected callable: $name');
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComprehensionAudioPlayer(
            storagePath: 'schools/school_x/comprehension_audio/log_x.m4a',
            schoolId: 'school_x',
            logId: 'log_x',
            durationSec: 4,
            audioService: service,
            debugSkipPlayerInitialization: true,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Delete recording'));
    await tester.pumpAndSettle();
    expect(find.text('Delete recording?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(deleteCalls, 1);
    expect(usedLimitedToken, isTrue);
    expect(find.byTooltip('Delete recording'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
