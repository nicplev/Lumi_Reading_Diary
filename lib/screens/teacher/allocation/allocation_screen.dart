import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
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
      backgroundColor: AppColors.teacherBackground,
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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Container(
            color: AppColors.white,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _buildPillTabBar(),
          ),
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

  Widget _buildPillTabBar() {
    return AnimatedBuilder(
      animation: _tabController,
      builder: (context, _) {
        final currentIndex = _tabController.index;
        return Container(
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.teacherPrimaryLight,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Row(
            children: [
              _buildPillTab('New Allocation', 0, currentIndex),
              _buildPillTab('Active Allocations', 1, currentIndex),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPillTab(String label, int index, int currentIndex) {
    final isSelected = index == currentIndex;
    return Expanded(
      child: GestureDetector(
        onTap: () => _tabController.animateTo(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.white : AppColors.teacherPrimaryLight,
            borderRadius: BorderRadius.circular(25),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColors.charcoal.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 13,
                fontWeight:
                    isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? AppColors.teacherPrimary
                    : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
