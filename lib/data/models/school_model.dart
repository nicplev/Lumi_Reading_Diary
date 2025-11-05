import 'package:cloud_firestore/cloud_firestore.dart';

enum ReadingLevelSchema {
  aToZ,
  pmBenchmark,
  lexile,
  custom,
}

class SchoolModel {
  final String id;
  final String name;
  final String? logoUrl;
  final String? primaryColor;
  final String? secondaryColor;
  final ReadingLevelSchema levelSchema;
  final List<String>? customLevels;
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

  SchoolModel({
    required this.id,
    required this.name,
    this.logoUrl,
    this.primaryColor,
    this.secondaryColor,
    required this.levelSchema,
    this.customLevels,
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
  });

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
    };
  }

  List<String> get readingLevels {
    switch (levelSchema) {
      case ReadingLevelSchema.aToZ:
        return [
          'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J',
          'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T',
          'U', 'V', 'W', 'X', 'Y', 'Z'
        ];
      case ReadingLevelSchema.pmBenchmark:
        return List.generate(30, (i) => '${i + 1}');
      case ReadingLevelSchema.lexile:
        return [
          'BR', '100L', '200L', '300L', '400L', '500L',
          '600L', '700L', '800L', '900L', '1000L', '1100L',
          '1200L', '1300L', '1400L'
        ];
      case ReadingLevelSchema.custom:
        return customLevels ?? [];
    }
  }
}