import 'package:cloud_firestore/cloud_firestore.dart';

import 'comprehension_recording_settings.dart';
import 'messaging_settings.dart';
import 'parent_comment_settings.dart';
import 'quick_logging_settings.dart';

enum ReadingLevelSchema {
  none,
  aToZ,
  pmBenchmark,
  lexile,
  numbered,
  namedLevels,
  colouredLevels,
  custom,
}

class SchoolModel {
  static const aiEvaluationAuthorityVersion = 'school-ai-eval-v1-2026-07-20';
  final String id;
  final String name;
  final String? logoUrl;
  final String? primaryColor;
  final String? secondaryColor;
  final ReadingLevelSchema levelSchema;
  final List<String>? customLevels;
  final Map<String, String>?
      levelColors; // hex color keyed by level name (for colouredLevels)
  final Map<String, DateTime> termDates; // term1Start, term1End, etc.
  final Map<String, String> quietHours; // start: "19:00", end: "07:00"
  final String timezone;
  final String? address;
  final String? contactEmail;
  final String? contactPhone;
  final bool isActive;
  final DateTime createdAt;
  final String createdBy;
  final Map<String, dynamic>? settings;
  final int studentCount;
  final int teacherCount;
  final String? subscriptionPlan;
  final DateTime? subscriptionExpiry;

  /// Materialised whole-school access verdict, written server-side by the
  /// subscription trigger / rollover cron / offboard wizard. Null on legacy
  /// documents — treated as active for back-compat reads (whole-school
  /// suspension is opt-in, set explicitly when a school stops paying).
  final SchoolAccess? access;

  SchoolModel({
    required this.id,
    required this.name,
    this.logoUrl,
    this.primaryColor,
    this.secondaryColor,
    required this.levelSchema,
    this.customLevels,
    this.levelColors,
    required this.termDates,
    required this.quietHours,
    required this.timezone,
    this.address,
    this.contactEmail,
    this.contactPhone,
    this.isActive = true,
    required this.createdAt,
    required this.createdBy,
    this.settings,
    this.studentCount = 0,
    this.teacherCount = 0,
    this.subscriptionPlan,
    this.subscriptionExpiry,
    this.access,
  });

  /// Fail-closed for staff/family gating: a school is suspended only when an
  /// explicit `access.status == 'suspended'` is present. Null access (legacy)
  /// reads as active.
  bool get isSuspended => access?.status == SchoolAccess.statusSuspended;

  factory SchoolModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SchoolModel(
      id: doc.id,
      name: data['name'] ?? '',
      logoUrl: data['logoUrl'],
      primaryColor: data['primaryColor'],
      secondaryColor: data['secondaryColor'],
      levelSchema: ReadingLevelSchema.values.firstWhere(
        (e) => e.toString() == 'ReadingLevelSchema.${data['levelSchema']}',
        orElse: () => ReadingLevelSchema.aToZ,
      ),
      customLevels: data['customLevels'] != null
          ? List<String>.from(data['customLevels'])
          : null,
      levelColors: data['levelColors'] != null
          ? Map<String, String>.from(data['levelColors'])
          : null,
      termDates: Map<String, DateTime>.from(
        (data['termDates'] ?? {}).map(
          (key, value) => MapEntry(key, (value as Timestamp).toDate()),
        ),
      ),
      quietHours: Map<String, String>.from(data['quietHours'] ?? {}),
      timezone: data['timezone'] ?? 'UTC',
      address: data['address'],
      contactEmail: data['contactEmail'],
      contactPhone: data['contactPhone'],
      isActive: data['isActive'] ?? true,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      createdBy: data['createdBy'] ?? '',
      settings: data['settings'],
      studentCount: data['studentCount'] ?? 0,
      teacherCount: data['teacherCount'] ?? 0,
      subscriptionPlan: data['subscriptionPlan'],
      subscriptionExpiry: data['subscriptionExpiry'] != null
          ? (data['subscriptionExpiry'] as Timestamp).toDate()
          : null,
      access: data['access'] != null
          ? SchoolAccess.fromMap(
              Map<String, dynamic>.from(data['access'] as Map))
          : null,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'logoUrl': logoUrl,
      'primaryColor': primaryColor,
      'secondaryColor': secondaryColor,
      'levelSchema': levelSchema.toString().split('.').last,
      'customLevels': customLevels,
      'levelColors': levelColors,
      'termDates': termDates.map(
        (key, value) => MapEntry(key, Timestamp.fromDate(value)),
      ),
      'quietHours': quietHours,
      'timezone': timezone,
      'address': address,
      'contactEmail': contactEmail,
      'contactPhone': contactPhone,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
      'createdBy': createdBy,
      'settings': settings,
      'studentCount': studentCount,
      'teacherCount': teacherCount,
      'subscriptionPlan': subscriptionPlan,
      'subscriptionExpiry': subscriptionExpiry != null
          ? Timestamp.fromDate(subscriptionExpiry!)
          : null,
      // Authoritative writer is server-side; included for full-doc round-trip.
      if (access != null) 'access': access!.toMap(),
    };
  }

  ParentCommentSettings get parentCommentSettings {
    return ParentCommentSettings.fromMap(
      settings?['parentComments'] as Map<String, dynamic>?,
    );
  }

  QuickLoggingSettings get quickLoggingSettings {
    return QuickLoggingSettings.fromMap(
      settings?['quickLogging'] as Map<String, dynamic>?,
    );
  }

  ComprehensionRecordingSettings get comprehensionRecordingSettings {
    return ComprehensionRecordingSettings.fromMap(
      settings?['comprehensionRecording'] as Map<String, dynamic>?,
    );
  }

  MessagingSettings get messagingSettings {
    return MessagingSettings.fromMap(
      settings?['messaging'] as Map<String, dynamic>?,
    );
  }

  /// AI comprehension evaluation entitlement. Written only by the Lumi team
  /// (super-admin portal); FAIL-CLOSED unless the switch, current authority
  /// version and server-stamped confirmation all match the server-side gate.
  bool get aiEvaluationEnabled {
    final ai = settings?['aiEvaluation'];
    return ai is Map &&
        ai['enabled'] == true &&
        ai['authorityVersion'] == aiEvaluationAuthorityVersion &&
        ai['authorityConfirmedAt'] != null;
  }

  bool get hasReadingLevels => levelSchema != ReadingLevelSchema.none;

  List<String> get readingLevels {
    switch (levelSchema) {
      case ReadingLevelSchema.none:
        return [];
      case ReadingLevelSchema.aToZ:
        return [
          'A',
          'B',
          'C',
          'D',
          'E',
          'F',
          'G',
          'H',
          'I',
          'J',
          'K',
          'L',
          'M',
          'N',
          'O',
          'P',
          'Q',
          'R',
          'S',
          'T',
          'U',
          'V',
          'W',
          'X',
          'Y',
          'Z'
        ];
      case ReadingLevelSchema.pmBenchmark:
        return List.generate(30, (i) => '${i + 1}');
      case ReadingLevelSchema.lexile:
        return [
          'BR',
          '100L',
          '200L',
          '300L',
          '400L',
          '500L',
          '600L',
          '700L',
          '800L',
          '900L',
          '1000L',
          '1100L',
          '1200L',
          '1300L',
          '1400L'
        ];
      case ReadingLevelSchema.numbered:
        return List.generate(100, (i) => '${i + 1}');
      case ReadingLevelSchema.namedLevels:
      case ReadingLevelSchema.colouredLevels:
        return customLevels ?? [];
      case ReadingLevelSchema.custom:
        return customLevels ?? [];
    }
  }
}

/// Materialised whole-school access verdict. Mirrors the `school.access` map
/// written server-side by the subscription trigger, rollover cron, and
/// off-board wizard. Drives whole-school suspension for staff and families.
class SchoolAccess {
  static const String statusActive = 'active';
  static const String statusSuspended = 'suspended';

  final String status;
  final int academicYear;
  final String? reason;
  final DateTime? updatedAt;

  SchoolAccess({
    required this.status,
    required this.academicYear,
    this.reason,
    this.updatedAt,
  });

  factory SchoolAccess.fromMap(Map<String, dynamic> map) {
    return SchoolAccess(
      status: map['status'] as String? ?? statusActive,
      academicYear: (map['academicYear'] as num?)?.toInt() ?? 0,
      reason: map['reason'] as String?,
      updatedAt: map['updatedAt'] != null
          ? (map['updatedAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'status': status,
      'academicYear': academicYear,
      if (reason != null) 'reason': reason,
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
    };
  }
}
