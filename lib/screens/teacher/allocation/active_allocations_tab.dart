import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';
import '../../../core/widgets/lumi/lumi_card.dart';
import '../../../core/widgets/lumi/lumi_toast.dart';
import '../../../data/models/user_model.dart';
import '../../../data/models/class_model.dart';
import '../../../data/models/allocation_model.dart';
import '../../../data/models/reading_level_option.dart';
import '../../../services/allocation_crud_service.dart';
import '../../../services/firebase_service.dart';
import '../../../services/reading_level_service.dart';
import 'allocation_card.dart';

class ActiveAllocationsTab extends StatefulWidget {
  final UserModel teacher;
  final ClassModel? selectedClass;
  final ValueChanged<AllocationModel> onEditAllocation;

  const ActiveAllocationsTab({
    super.key,
    required this.teacher,
    this.selectedClass,
    required this.onEditAllocation,
  });

  @override
  State<ActiveAllocationsTab> createState() => _ActiveAllocationsTabState();
}

class _ActiveAllocationsTabState extends State<ActiveAllocationsTab> {
  final _firebaseService = FirebaseService.instance;
  final _allocationCrudService = AllocationCrudService();
  final _readingLevelService = ReadingLevelService();
  List<ReadingLevelOption> _readingLevelOptions = const [];

  @override
  void initState() {
    super.initState();
    _loadReadingLevelOptions();
  }

  Future<void> _loadReadingLevelOptions() async {
    final schoolId = widget.teacher.schoolId;
    if (schoolId == null || schoolId.isEmpty) return;
    try {
      final options = await _readingLevelService.loadSchoolLevels(schoolId);
      if (mounted) {
        setState(() => _readingLevelOptions = options);
      }
    } catch (_) {}
  }

  String _formatLevelLabel(String? value) {
    if (value == null || value.trim().isEmpty) return 'Not set';
    if (_readingLevelOptions.isEmpty) return value.trim();
    return _readingLevelService.formatLevelLabel(
      value,
      options: _readingLevelOptions,
    );
  }

  String _formatLevelRangeLabel(String? start, String? end) {
    if (start == null || start.trim().isEmpty) return 'Level not set';
    final startLabel = _formatLevelLabel(start);
    if (end == null || end.trim().isEmpty) return startLabel;
    final endLabel = _formatLevelLabel(end);
    return '$startLabel – $endLabel';
  }

  Future<void> _deleteAllocation(AllocationModel allocation) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: LumiTokens.paper,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LumiTokens.radiusXL),
        ),
        title: Text('Delete Allocation', style: LumiType.subhead),
        content: Text(
          'Are you sure you want to delete this allocation? This cannot be undone.',
          style: LumiType.body.copyWith(color: LumiTokens.ink),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: LumiType.button.copyWith(color: LumiTokens.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete',
                style: LumiType.button.copyWith(color: LumiTokens.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _allocationCrudService.updateAllocation(
          schoolId: widget.teacher.schoolId!,
          allocationId: allocation.id,
          actorId: widget.teacher.id,
          isActive: false,
        );
        showLumiToast(
          message: 'Allocation removed.',
          type: LumiToastType.success,
        );
      } catch (_) {
        showLumiToast(
          message: "Couldn't remove the allocation. Please try again.",
          type: LumiToastType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.selectedClass == null) {
      return Center(
        child: LumiEmptyCard(
          icon: Icons.class_,
          title: 'No class selected',
          message: 'Please select a class from the dashboard.',
          accentColor: LumiTokens.green,
        ),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _firebaseService.firestore
          .collection('schools')
          .doc(widget.teacher.schoolId!)
          .collection('allocations')
          .where('classId', isEqualTo: widget.selectedClass!.id)
          .where('isActive', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: LumiEmptyCard(
              icon: Icons.error_outline,
              title: 'Error loading allocations',
              message: snapshot.error.toString(),
              accentColor: LumiTokens.red,
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: LumiTokens.green),
          );
        }

        final now = DateTime.now();
        final allocations = snapshot.data!.docs
            .map((doc) => AllocationModel.fromFirestore(doc))
            .where((a) => a.endDate.isAfter(now))
            .toList();

        if (allocations.isEmpty) {
          return Center(
            child: LumiEmptyCard(
              icon: Icons.assignment_outlined,
              title: 'No active allocations',
              message:
                  'Create a new allocation to assign reading to your students.',
              accentColor: LumiTokens.green,
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: allocations.length,
          itemBuilder: (context, index) {
            final allocation = allocations[index];
            return AllocationCard(
              allocation: allocation,
              levelRangeFormatter: _formatLevelRangeLabel,
              onEdit: () => widget.onEditAllocation(allocation),
              onDelete: () => _deleteAllocation(allocation),
            );
          },
        );
      },
    );
  }
}
