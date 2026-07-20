import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../theme/lumi_tokens.dart';

/// One AI comprehension evaluation — the read model for
/// `schools/{schoolId}/comprehensionEvals/{logId}` (doc id == logId).
///
/// Server-written only; parsing is tolerant so unknown statuses, levels or
/// flags from newer pipeline versions pass through without crashing older
/// app builds. NO numeric score is ever exposed to UI — levels + confidence
/// only (the server-side `sortKey` is deliberately not parsed).
class ComprehensionEvalModel {
  final String logId;
  final String schoolId;
  final String studentId;
  final String classId;
  final DateTime? logDate;
  final String status; // complete | flagged | failed | skipped
  final DateTime? audioUploadedAt;
  final String? transcript;
  final DateTime? transcriptRemovedAt;
  final int transcriptChars;
  final double? sttConfidence;
  final String? questionTextUsed;
  final String? questionSource; // log | classCurrent | default
  final List<String> questionCategories;
  final String? rubricKey;
  final int rubricVersion;
  final String? summary;
  final List<CriterionScore> criterionScores;
  final String? overallLevel; // not_evident | emerging | developing | secure
  final String? confidence; // low | medium | high
  final List<String> flags;
  final bool assessable;
  final String? model;
  final int promptVersion;
  final DateTime? evaluatedAt;

  const ComprehensionEvalModel({
    required this.logId,
    required this.schoolId,
    required this.studentId,
    required this.classId,
    this.logDate,
    required this.status,
    this.audioUploadedAt,
    this.transcript,
    this.transcriptRemovedAt,
    this.transcriptChars = 0,
    this.sttConfidence,
    this.questionTextUsed,
    this.questionSource,
    this.questionCategories = const [],
    this.rubricKey,
    this.rubricVersion = 1,
    this.summary,
    this.criterionScores = const [],
    this.overallLevel,
    this.confidence,
    this.flags = const [],
    required this.assessable,
    this.model,
    this.promptVersion = 1,
    this.evaluatedAt,
  });

  factory ComprehensionEvalModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return ComprehensionEvalModel.fromMap(doc.id, data);
  }

  factory ComprehensionEvalModel.fromMap(
      String logId, Map<String, dynamic> data) {
    List<String> stringList(dynamic value) => value is List
        ? value.whereType<String>().toList(growable: false)
        : const [];
    return ComprehensionEvalModel(
      logId: logId,
      schoolId: data['schoolId'] as String? ?? '',
      studentId: data['studentId'] as String? ?? '',
      classId: data['classId'] as String? ?? '',
      logDate: (data['logDate'] as Timestamp?)?.toDate(),
      status: data['status'] as String? ?? 'failed',
      audioUploadedAt: (data['audioUploadedAt'] as Timestamp?)?.toDate(),
      transcript: data['transcript'] as String?,
      transcriptRemovedAt:
          (data['transcriptRemovedAt'] as Timestamp?)?.toDate(),
      transcriptChars: (data['transcriptChars'] as num?)?.toInt() ?? 0,
      sttConfidence: (data['sttConfidence'] as num?)?.toDouble(),
      questionTextUsed: data['questionTextUsed'] as String?,
      questionSource: data['questionSource'] as String?,
      questionCategories: stringList(data['questionCategories']),
      rubricKey: data['rubricKey'] as String?,
      rubricVersion: (data['rubricVersion'] as num?)?.toInt() ?? 1,
      summary: data['summary'] as String?,
      criterionScores: data['criterionScores'] is List
          ? (data['criterionScores'] as List)
              .whereType<Map>()
              .map((m) => CriterionScore.fromMap(m.cast<String, dynamic>()))
              .toList(growable: false)
          : const [],
      overallLevel: data['overallLevel'] as String?,
      confidence: data['confidence'] as String?,
      flags: stringList(data['flags']),
      assessable: data['assessable'] == true,
      model: data['model'] as String?,
      promptVersion: (data['promptVersion'] as num?)?.toInt() ?? 1,
      evaluatedAt: (data['evaluatedAt'] as Timestamp?)?.toDate(),
    );
  }

  bool get isScored => assessable && overallLevel != null;
  bool get needsReview => status == 'flagged' || status == 'failed';

  /// True when the recording was replaced AFTER this evaluation ran — the
  /// teacher would hear different audio than the eval describes.
  bool audioReplacedSince(DateTime? logAudioUploadedAt) {
    if (audioUploadedAt == null || logAudioUploadedAt == null) return false;
    return logAudioUploadedAt.isAfter(audioUploadedAt!);
  }

  static const levelOrder = [
    'not_evident',
    'emerging',
    'developing',
    'secure',
  ];

  static String levelLabel(String? level) {
    switch (level) {
      case 'not_evident':
        return 'Not evident';
      case 'emerging':
        return 'Emerging';
      case 'developing':
        return 'Developing';
      case 'secure':
        return 'Secure';
      default:
        return 'No result';
    }
  }

  static Color levelColor(String? level) {
    switch (level) {
      case 'secure':
        return LumiTokens.green;
      case 'developing':
        return LumiTokens.blue;
      case 'emerging':
        return LumiTokens.yellow;
      case 'not_evident':
        return LumiTokens.red;
      default:
        return LumiTokens.muted;
    }
  }

  static String confidenceLabel(String? confidence) {
    switch (confidence) {
      case 'high':
        return 'High confidence';
      case 'medium':
        return 'Medium confidence';
      case 'low':
        return 'Low confidence';
      default:
        return '';
    }
  }

  /// Teacher-facing labels for pipeline flags. Unknown flags fall back to a
  /// humanised form so newer pipeline flags never render as raw slugs.
  static String flagLabel(String flag) {
    switch (flag) {
      case 'too_short':
        return 'Recording too short';
      case 'inaudible':
        return 'Inaudible';
      case 'off_topic':
        return 'Off topic';
      case 'non_english':
        return 'Non-English';
      case 'low_stt_confidence':
        return 'Unclear audio';
      case 'question_mismatch':
        return 'Question mismatch';
      case 'concerning_content':
        return 'Needs review';
      case 'audio_unavailable':
        return 'Recording unavailable';
      case 'system_error':
        return "Couldn't evaluate";
      case 'prompt_injection':
        return 'Unusual content';
      case 'adult_prompting':
        return 'Adult prompting';
      case 'recitation_blocked':
        return 'Read aloud verbatim';
      case 'empty_response':
        return 'No answer detected';
      case 'unsupported_self_assessment':
        return 'Self-grading detected';
      case 'incidental_personal_info':
        return 'Personal info mentioned';
      default:
        return flag.replaceAll('_', ' ');
    }
  }
}

class CriterionScore {
  final String criterionId;
  final int score; // 0-3
  final String evidence;

  const CriterionScore({
    required this.criterionId,
    required this.score,
    required this.evidence,
  });

  factory CriterionScore.fromMap(Map<String, dynamic> map) {
    return CriterionScore(
      criterionId: map['criterionId'] as String? ?? '',
      score: ((map['score'] as num?)?.toInt() ?? 0).clamp(0, 3),
      evidence: map['evidence'] as String? ?? '',
    );
  }

  String get label {
    switch (criterionId) {
      case 'recall':
        return 'Recalls events';
      case 'sequence':
        return 'Orders events';
      case 'detail':
        return 'Supporting detail';
      case 'inference':
        return 'Makes an inference';
      case 'text_support':
        return 'Supports from the text';
      case 'plausibility':
        return 'Plausibility';
      case 'word_meaning':
        return 'Word meaning';
      case 'context_use':
        return 'Uses context';
      case 'connection':
        return 'Makes a connection';
      case 'book_link':
        return 'Linked to the book';
      // Ids are mapped globally, so this is whichever rubric produced the
      // eval. Since rubric v2 only the general rubric uses 'relevance', where
      // it means "answers the question". Personal-connection evals written
      // under rubric v1 also carry this id and will read slightly off — they
      // meant "the connection relates to the reading content" — but there is
      // no rubric key stored per criterion to disambiguate, and v1 evals age
      // out with the 730-day retention.
      case 'relevance':
        return 'Answers the question';
      case 'understanding':
        return 'Shows understanding';
      case 'expression':
        return 'Expresses ideas';
      case 'elaboration':
        return 'Elaboration';
      default:
        return criterionId.replaceAll('_', ' ');
    }
  }
}
