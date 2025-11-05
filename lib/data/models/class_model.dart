import 'package:cloud_firestore/cloud_firestore.dart';

class ClassModel {
  final String id;
  final String schoolId;
  final String name;
  final String? yearLevel;
  final String? room;
  final String teacherId; // Primary teacher (kept for backwards compatibility)
  final String? assistantTeacherId; // Kept for backwards compatibility
  final List<String> teacherIds; // List of all assigned teacher IDs
  final List<String> studentIds;
  final int defaultMinutesTarget;
  final String? description;
  final bool isActive;
  final DateTime createdAt;
  final String createdBy;
  final Map<String, dynamic>? settings;

  ClassModel({
    required this.id,
    required this.schoolId,
    required this.name,
    this.yearLevel,
    this.room,
    required this.teacherId,
    this.assistantTeacherId,
    List<String>? teacherIds,
    required this.studentIds,
    this.defaultMinutesTarget = 20,
    this.description,
    this.isActive = true,
    required this.createdAt,
    required this.createdBy,
    this.settings,
  }) : teacherIds = teacherIds ?? [teacherId];

  factory ClassModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final teacherId = data['teacherId'] ?? '';

    // Handle both old and new data structures
    List<String> teacherIds;
    if (data['teacherIds'] != null) {
      teacherIds = List<String>.from(data['teacherIds']);
    } else {
      // Backwards compatibility: build teacherIds from old fields
      teacherIds = [
        if (teacherId.isNotEmpty) teacherId,
        if (data['assistantTeacherId'] != null && (data['assistantTeacherId'] as String).isNotEmpty)
          data['assistantTeacherId'] as String,
      ];
      if (teacherIds.isEmpty) teacherIds = [''];
    }

    return ClassModel(
      id: doc.id,
      schoolId: data['schoolId'] ?? '',
      name: data['name'] ?? '',
      yearLevel: data['yearLevel'],
      room: data['room'],
      teacherId: teacherId,
      assistantTeacherId: data['assistantTeacherId'],
      teacherIds: teacherIds,
      studentIds: List<String>.from(data['studentIds'] ?? []),
      defaultMinutesTarget: data['defaultMinutesTarget'] ?? 20,
      description: data['description'],
      isActive: data['isActive'] ?? true,
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      createdBy: data['createdBy'] ?? '',
      settings: data['settings'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'schoolId': schoolId,
      'name': name,
      'yearLevel': yearLevel,
      'room': room,
      'teacherId': teacherId,
      'assistantTeacherId': assistantTeacherId,
      'teacherIds': teacherIds, // Include the new field
      'studentIds': studentIds,
      'defaultMinutesTarget': defaultMinutesTarget,
      'description': description,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
      'createdBy': createdBy,
      'settings': settings,
    };
  }

  ClassModel copyWith({
    String? id,
    String? schoolId,
    String? name,
    String? yearLevel,
    String? room,
    String? teacherId,
    String? assistantTeacherId,
    List<String>? teacherIds,
    List<String>? studentIds,
    int? defaultMinutesTarget,
    String? description,
    bool? isActive,
    DateTime? createdAt,
    String? createdBy,
    Map<String, dynamic>? settings,
  }) {
    return ClassModel(
      id: id ?? this.id,
      schoolId: schoolId ?? this.schoolId,
      name: name ?? this.name,
      yearLevel: yearLevel ?? this.yearLevel,
      room: room ?? this.room,
      teacherId: teacherId ?? this.teacherId,
      assistantTeacherId: assistantTeacherId ?? this.assistantTeacherId,
      teacherIds: teacherIds ?? this.teacherIds,
      studentIds: studentIds ?? this.studentIds,
      defaultMinutesTarget: defaultMinutesTarget ?? this.defaultMinutesTarget,
      description: description ?? this.description,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
      settings: settings ?? this.settings,
    );
  }
}