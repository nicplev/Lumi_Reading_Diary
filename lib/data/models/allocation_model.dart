import 'package:cloud_firestore/cloud_firestore.dart';

enum AllocationCadence {
  daily,
  weekly,
  fortnightly,
  custom,
}

enum AllocationType {
  byLevel, // Level band allocation
  byTitle, // Specific book titles
  freeChoice, // Student chooses within level
}

class AllocationModel {
  final String id;
  final String schoolId;
  final String classId;
  final String teacherId;
  final List<String> studentIds; // Can be whole class or specific students
  final AllocationType type;
  final AllocationCadence cadence;
  final int targetMinutes;
  final DateTime startDate;
  final DateTime endDate;

  // For level-based allocation
  final String? levelStart;
  final String? levelEnd;

  // For title-based allocation
  final List<String>? bookIds;
  final List<String>? bookTitles; // For free text titles

  final bool isRecurring;
  final String? templateName; // For saving as template
  final bool isActive;
  final DateTime createdAt;
  final String createdBy;
  final Map<String, dynamic>? metadata;

  AllocationModel({
    required this.id,
    required this.schoolId,
    required this.classId,
    required this.teacherId,
    required this.studentIds,
    required this.type,
    required this.cadence,
    required this.targetMinutes,
    required this.startDate,
    required this.endDate,
    this.levelStart,
    this.levelEnd,
    this.bookIds,
    this.bookTitles,
    this.isRecurring = false,
    this.templateName,
    this.isActive = true,
    required this.createdAt,
    required this.createdBy,
    this.metadata,
  });

  bool get isForWholeClass => studentIds.isEmpty;

  factory AllocationModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AllocationModel(
      id: doc.id,
      schoolId: data['schoolId'] ?? '',
      classId: data['classId'] ?? '',
      teacherId: data['teacherId'] ?? '',
      studentIds: List<String>.from(data['studentIds'] ?? []),
      type: AllocationType.values.firstWhere(
        (e) => e.toString() == 'AllocationType.${data['type']}',
        orElse: () => AllocationType.byLevel,
      ),
      cadence: AllocationCadence.values.firstWhere(
        (e) => e.toString() == 'AllocationCadence.${data['cadence']}',
        orElse: () => AllocationCadence.weekly,
      ),
      targetMinutes: data['targetMinutes'] ?? 20,
      startDate: (data['startDate'] as Timestamp).toDate(),
      endDate: (data['endDate'] as Timestamp).toDate(),
      levelStart: data['levelStart'],
      levelEnd: data['levelEnd'],
      bookIds: data['bookIds'] != null
          ? List<String>.from(data['bookIds'])
          : null,
      bookTitles: data['bookTitles'] != null
          ? List<String>.from(data['bookTitles'])
          : null,
      isRecurring: data['isRecurring'] ?? false,
      templateName: data['templateName'],
      isActive: data['isActive'] ?? true,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      createdBy: data['createdBy'] ?? '',
      metadata: data['metadata'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'schoolId': schoolId,
      'classId': classId,
      'teacherId': teacherId,
      'studentIds': studentIds,
      'type': type.toString().split('.').last,
      'cadence': cadence.toString().split('.').last,
      'targetMinutes': targetMinutes,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'levelStart': levelStart,
      'levelEnd': levelEnd,
      'bookIds': bookIds,
      'bookTitles': bookTitles,
      'isRecurring': isRecurring,
      'templateName': templateName,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
      'createdBy': createdBy,
      'metadata': metadata,
    };
  }

  AllocationModel copyWith({
    String? id,
    String? schoolId,
    String? classId,
    String? teacherId,
    List<String>? studentIds,
    AllocationType? type,
    AllocationCadence? cadence,
    int? targetMinutes,
    DateTime? startDate,
    DateTime? endDate,
    String? levelStart,
    String? levelEnd,
    List<String>? bookIds,
    List<String>? bookTitles,
    bool? isRecurring,
    String? templateName,
    bool? isActive,
    DateTime? createdAt,
    String? createdBy,
    Map<String, dynamic>? metadata,
  }) {
    return AllocationModel(
      id: id ?? this.id,
      schoolId: schoolId ?? this.schoolId,
      classId: classId ?? this.classId,
      teacherId: teacherId ?? this.teacherId,
      studentIds: studentIds ?? this.studentIds,
      type: type ?? this.type,
      cadence: cadence ?? this.cadence,
      targetMinutes: targetMinutes ?? this.targetMinutes,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      levelStart: levelStart ?? this.levelStart,
      levelEnd: levelEnd ?? this.levelEnd,
      bookIds: bookIds ?? this.bookIds,
      bookTitles: bookTitles ?? this.bookTitles,
      isRecurring: isRecurring ?? this.isRecurring,
      templateName: templateName ?? this.templateName,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
      metadata: metadata ?? this.metadata,
    );
  }
}