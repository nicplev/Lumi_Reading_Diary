import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/screens/parent/widgets/comprehension_recording_step.dart';

void main() {
  testWidgets('shared demo audio explains the local-only preview',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComprehensionRecordingStep(
            question: 'What happened in the story?',
            logId: 'demo-log',
            onRecordingChanged: (_) {},
            onSkip: () {},
            embedded: true,
            previewOnly: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Demo preview — try recording and playback. This audio is not uploaded or kept.',
      ),
      findsOneWidget,
    );
    expect(find.text('Record'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  test('discard removes a local demo-preview recording', () async {
    final directory = await Directory.systemTemp.createTemp('lumi-demo-audio-');
    final file = File('${directory.path}/preview.m4a');
    await file.writeAsBytes([0, 1, 2, 3]);

    await discardComprehensionRecordingPreview(
      ComprehensionRecordingResult(localPath: file.path, durationSec: 1),
    );

    expect(file.existsSync(), isFalse);
    await directory.delete(recursive: true);
  });
}
