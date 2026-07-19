import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../data/models/reading_group_model.dart';
import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';

/// Reading-group badges at the top of the teacher student-detail screen.
/// Owns its one-shot groups fetch; re-fires it when the student (or school)
/// changes, mirroring the screen's original didUpdateWidget semantics.
class GroupBadgesSection extends StatefulWidget {
  final FirebaseFirestore firestore;
  final String schoolId;
  final String classId;
  final String studentId;

  const GroupBadgesSection({
    super.key,
    required this.firestore,
    required this.schoolId,
    required this.classId,
    required this.studentId,
  });

  @override
  State<GroupBadgesSection> createState() => _GroupBadgesSectionState();
}

class _GroupBadgesSectionState extends State<GroupBadgesSection> {
  late Future<List<ReadingGroupModel>> _groupsFuture;

  @override
  void initState() {
    super.initState();
    _groupsFuture = _loadStudentGroups();
  }

  @override
  void didUpdateWidget(covariant GroupBadgesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.studentId != widget.studentId ||
        oldWidget.classId != widget.classId ||
        oldWidget.schoolId != widget.schoolId) {
      _groupsFuture = _loadStudentGroups();
    }
  }

  Future<List<ReadingGroupModel>> _loadStudentGroups() async {
    try {
      final snapshot = await widget.firestore
          .collection('schools')
          .doc(widget.schoolId)
          .collection('readingGroups')
          .where('classId', isEqualTo: widget.classId)
          .where('studentIds', arrayContains: widget.studentId)
          .where('isActive', isEqualTo: true)
          .get();
      return snapshot.docs
          .map((doc) => ReadingGroupModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('Error loading student groups: $e');
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ReadingGroupModel>>(
      future: _groupsFuture,
      builder: (context, snapshot) {
        final groups = snapshot.data;
        if (groups == null || groups.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: groups.map((group) {
              final groupColor = group.color != null
                  ? Color(int.parse(group.color!.replaceFirst('#', '0xFF')))
                  : LumiTokens.green;
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: groupColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
                  border: Border.all(
                    color: groupColor.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: groupColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      group.name,
                      style: LumiType.caption.copyWith(
                        color: groupColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}
