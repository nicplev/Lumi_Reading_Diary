import 'package:flutter/material.dart';

import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';
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
      backgroundColor: LumiTokens.cream,
      appBar: AppBar(
        title: Text(
          'Assign Books',
          style: LumiType.subhead,
        ),
        backgroundColor: LumiTokens.cream,
        foregroundColor: LumiTokens.ink,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Container(
            color: LumiTokens.cream,
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
            color: LumiTokens.green.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
          ),
          child: Row(
            children: [
              _buildPillTab('New', 0, currentIndex),
              _buildPillTab('Active', 1, currentIndex),
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
            color: isSelected ? LumiTokens.paper : Colors.transparent,
            borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: LumiTokens.ink.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: LumiType.caption.copyWith(
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? LumiTokens.green : LumiTokens.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
