import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/core/services/dev_access_service.dart';
import 'package:lumi_reading_tracker/data/models/comprehension_eval_model.dart';
import 'package:lumi_reading_tracker/data/providers/active_child_provider.dart'
    show firestoreProvider;
import 'package:lumi_reading_tracker/screens/teacher/student_detail/comprehension_section.dart';
import 'package:lumi_reading_tracker/data/providers/student_detail_providers.dart';

const lookup = StudentDetailLookup(
  schoolId: 'school1',
  classId: 'class1',
  studentId: 'stu1',
);

Future<void> pumpSection(
  WidgetTester tester,
  FakeFirebaseFirestore firestore,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [firestoreProvider.overrideWithValue(firestore)],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ComprehensionSection(
              lookup: lookup,
              studentName: 'Milo Smith',
            ),
          ),
        ),
      ),
    ),
  );
  // Gate stream -> section rebuild -> evals/logs streams -> body: allow a
  // few microtask/frame cycles for the chained streams to deliver.
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> seedGatesOn(FakeFirebaseFirestore firestore) async {
  await firestore
      .collection('platformConfig')
      .doc('aiEvaluation')
      .set({'enabled': true});
  await firestore.collection('schools').doc('school1').set({
    'name': 'Test School',
    'createdAt': Timestamp.fromDate(DateTime(2025, 1, 1)),
    'settings': {
      'aiEvaluation': {'enabled': true},
    },
  });
}

Future<void> seedEval(
  FakeFirebaseFirestore firestore, {
  String logId = 'log1',
  String level = 'developing',
  List<String> flags = const [],
}) async {
  await firestore
      .collection('schools')
      .doc('school1')
      .collection('comprehensionEvals')
      .doc(logId)
      .set({
    'schoolId': 'school1',
    'logId': logId,
    'studentId': 'stu1',
    'classId': 'class1',
    'logDate': Timestamp.fromDate(DateTime(2026, 7, 18)),
    'status': flags.isEmpty ? 'complete' : 'flagged',
    'audioUploadedAt': Timestamp.fromDate(DateTime(2026, 7, 18, 18)),
    'summary': 'The student recalled the main events clearly.',
    'criterionScores': [
      {'criterionId': 'recall', 'score': 2, 'evidence': 'the dog found a bone'},
    ],
    'overallLevel': level,
    'confidence': 'high',
    'flags': flags,
    'assessable': true,
    'evaluatedAt': Timestamp.fromDate(DateTime(2026, 7, 19)),
  });
}

void enableDevAccess() {
  final service = DevAccessService.debug(
    auth: MockFirebaseAuth(),
    callableInvoker: (name, data) async => {'allowed': false},
  );
  service.unlockForSession();
  DevAccessService.debugSetInstance(service);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  group('ComprehensionEvalModel', () {
    test('parses a full document tolerantly', () {
      final model = ComprehensionEvalModel.fromMap('log1', {
        'schoolId': 's1',
        'studentId': 'stu1',
        'classId': 'c1',
        'status': 'complete',
        'overallLevel': 'secure',
        'confidence': 'high',
        'assessable': true,
        'flags': ['off_topic', 42, null],
        'criterionScores': [
          {'criterionId': 'recall', 'score': 99, 'evidence': 'e'},
          'garbage',
        ],
        'summary': 'Great answer.',
      });
      expect(model.logId, 'log1');
      expect(model.overallLevel, 'secure');
      expect(model.flags, ['off_topic']);
      expect(model.criterionScores.length, 1);
      expect(model.criterionScores.first.score, 3); // clamped 0-3
      expect(model.isScored, isTrue);
    });

    test('unknown/absent fields never throw', () {
      final model = ComprehensionEvalModel.fromMap('x', {});
      expect(model.status, 'failed');
      expect(model.assessable, isFalse);
      expect(model.isScored, isFalse);
      expect(ComprehensionEvalModel.levelLabel(model.overallLevel),
          'No result');
    });

    test('audioReplacedSince compares upload stamps', () {
      final model = ComprehensionEvalModel.fromMap('x', {
        'audioUploadedAt': Timestamp.fromDate(DateTime(2026, 7, 18)),
        'status': 'complete',
        'assessable': true,
      });
      expect(model.audioReplacedSince(DateTime(2026, 7, 19)), isTrue);
      expect(model.audioReplacedSince(DateTime(2026, 7, 17)), isFalse);
      expect(model.audioReplacedSince(null), isFalse);
    });

    test('flag labels are teacher-facing for every pipeline flag', () {
      for (final flag in [
        'too_short', 'inaudible', 'off_topic', 'non_english',
        'low_stt_confidence', 'question_mismatch', 'concerning_content',
        'audio_unavailable', 'system_error', 'prompt_injection',
        'adult_prompting', 'recitation_blocked', 'empty_response',
        'unsupported_self_assessment', 'incidental_personal_info',
      ]) {
        expect(ComprehensionEvalModel.flagLabel(flag), isNot(contains('_')));
      }
      // Unknown future flags humanise instead of crashing.
      expect(ComprehensionEvalModel.flagLabel('brand_new_flag'),
          'brand new flag');
    });
  });

  group('ComprehensionSection gating', () {
    testWidgets('renders nothing when the platform switch is off',
        (tester) async {
      enableDevAccess();
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('schools').doc('school1').set({
        'settings': {
          'aiEvaluation': {'enabled': true},
        },
      });
      await seedEval(firestore);
      await pumpSection(tester, firestore);
      expect(find.text('Comprehension'), findsNothing);
    });

    testWidgets('renders nothing when the school entitlement is off',
        (tester) async {
      enableDevAccess();
      final firestore = FakeFirebaseFirestore();
      await firestore
          .collection('platformConfig')
          .doc('aiEvaluation')
          .set({'enabled': true});
      await firestore.collection('schools').doc('school1').set({
        'createdAt': Timestamp.fromDate(DateTime(2025, 1, 1)),
        'settings': {},
      });
      await seedEval(firestore);
      await pumpSection(tester, firestore);
      expect(find.text('Comprehension'), findsNothing);
    });

    testWidgets('shows the latest eval when gates + dev access are on',
        (tester) async {
      enableDevAccess();
      final firestore = FakeFirebaseFirestore();
      await seedGatesOn(firestore);
      await seedEval(firestore);
      await pumpSection(tester, firestore);
      expect(find.text('Comprehension'), findsOneWidget);
      expect(find.text('Developing'), findsOneWidget);
      expect(find.text('The student recalled the main events clearly.'),
          findsOneWidget);
      expect(find.textContaining('professional judgement'), findsOneWidget);
    });

    testWidgets('empty state renders when entitled but no evals',
        (tester) async {
      enableDevAccess();
      final firestore = FakeFirebaseFirestore();
      await seedGatesOn(firestore);
      await pumpSection(tester, firestore);
      expect(
          find.text('No comprehension evaluations yet'), findsOneWidget);
    });

    testWidgets('flagged eval shows teacher-facing flag chips',
        (tester) async {
      enableDevAccess();
      final firestore = FakeFirebaseFirestore();
      await seedGatesOn(firestore);
      await seedEval(firestore,
          flags: ['low_stt_confidence', 'adult_prompting']);
      await pumpSection(tester, firestore);
      expect(find.text('Unclear audio'), findsOneWidget);
      expect(find.text('Adult prompting'), findsOneWidget);
    });
  });
}
