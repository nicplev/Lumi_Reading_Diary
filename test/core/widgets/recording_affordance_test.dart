import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/core/widgets/comments/teacher_comments_sheet.dart';
import 'package:lumi_reading_tracker/data/models/school_model.dart';
import 'package:lumi_reading_tracker/data/providers/access_provider.dart';
import 'package:lumi_reading_tracker/data/providers/school_settings_provider.dart';

void main() {
  Widget subject({
    required bool schoolEnabled,
    required bool platformEnabled,
  }) {
    final school = SchoolModel(
      id: 'school-1',
      name: 'Test School',
      levelSchema: ReadingLevelSchema.aToZ,
      termDates: const {},
      quietHours: const {},
      timezone: 'Australia/Melbourne',
      createdAt: DateTime(2026),
      createdBy: 'test',
      settings: <String, dynamic>{
        'comprehensionRecording': <String, dynamic>{
          'enabled': schoolEnabled,
        },
      },
    );
    return ProviderScope(
      overrides: [
        schoolByIdProvider.overrideWith(
          (ref, schoolId) => Stream.value(school),
        ),
        platformComprehensionAudioEnabledProvider.overrideWith(
          (ref) => Stream.value(platformEnabled),
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: RecordingAffordance(schoolId: 'school-1'),
        ),
      ),
    );
  }

  testWidgets('hides the microphone when school audio is disabled',
      (tester) async {
    await tester.pumpWidget(subject(
      schoolEnabled: false,
      platformEnabled: true,
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.mic_rounded), findsNothing);
  });

  testWidgets('shows the microphone when school audio is enabled',
      (tester) async {
    await tester.pumpWidget(subject(
      schoolEnabled: true,
      platformEnabled: true,
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
  });

  testWidgets('hides the microphone when the platform switch is off',
      (tester) async {
    await tester.pumpWidget(subject(
      schoolEnabled: true,
      platformEnabled: false,
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.mic_rounded), findsNothing);
  });
}
