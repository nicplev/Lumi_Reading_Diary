import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/teacher_constants.dart';
import '../../../data/models/user_model.dart';
import '../../../data/models/class_model.dart';
import '../../../data/models/allocation_model.dart';
import 'new_allocation_tab.dart';
import 'active_allocations_tab.dart';

class AllocationScreen extends StatefulWidget {
  final UserModel teacher;
  final ClassModel? selectedClass;
  final String? preselectedStudentId;

  const AllocationScreen({
    super.key,
    required this.teacher,
    this.selectedClass,
    this.preselectedStudentId,
  });

  @override
  State<AllocationScreen> createState() => _AllocationScreenState();
}

class _AllocationScreenState extends State<AllocationScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Edit mode: when a user taps Edit on an active allocation,
  // we switch to tab 0 and pass the allocation to pre-populate.
  AllocationModel? _editingAllocation;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onEditAllocation(AllocationModel allocation) {
    setState(() {
      _editingAllocation = allocation;
    });
    _tabController.animateTo(0);
  }

  void _onEditCancelled() {
    setState(() {
      _editingAllocation = null;
    });
  }

  void _onAllocationSaved() {
    setState(() {
      _editingAllocation = null;
    });
    _tabController.animateTo(1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Reading Allocation',
          style: TextStyle(
            fontFamily: 'Nunito',
            fontWeight: FontWeight.w700,
            color: AppColors.charcoal,
          ),
        ),
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.charcoal,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'New Allocation'),
            Tab(text: 'Active Allocations'),
          ],
          labelColor: AppColors.teacherPrimary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.teacherPrimary,
          indicatorWeight: 3,
          labelStyle: TeacherTypography.bodyMedium
              .copyWith(fontWeight: FontWeight.w700),
          unselectedLabelStyle: TeacherTypography.bodyMedium,
          dividerColor: AppColors.teacherBorder,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          NewAllocationTab(
            teacher: widget.teacher,
            selectedClass: widget.selectedClass,
            preselectedStudentId: widget.preselectedStudentId,
            editingAllocation: _editingAllocation,
            onEditCancelled: _onEditCancelled,
            onSaved: _onAllocationSaved,
          ),
          ActiveAllocationsTab(
            teacher: widget.teacher,
            selectedClass: widget.selectedClass,
            onEditAllocation: _onEditAllocation,
          ),
        ],
      ),
    );
  }
}
