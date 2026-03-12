import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/teacher_constants.dart';
import '../../data/models/user_model.dart';
import '../../data/models/class_model.dart';
import '../../data/models/student_model.dart';
import '../../data/models/allocation_model.dart';
import '../../services/firebase_service.dart';

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
  final FirebaseService _firebaseService = FirebaseService.instance;

  // Form controllers
  final _minutesController = TextEditingController(text: '20');
  final _bookTitlesController = TextEditingController();
  final List<String> _bookTitles = [];

  // Selection state
  AllocationType _allocationType = AllocationType.freeChoice;
  AllocationCadence _cadence = AllocationCadence.weekly;
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 7));
  List<String> _selectedStudentIds = [];
  bool _selectAllStudents = true;
  String? _levelRangeStart;
  String? _levelRangeEnd;
  bool _isRecurring = false;
  String? _templateName;

  List<StudentModel> _students = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    if (widget.selectedClass != null) {
      _loadStudents();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _minutesController.dispose();
    _bookTitlesController.dispose();
    super.dispose();
  }

  Future<void> _loadStudents() async {
    if (widget.selectedClass == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final students = <StudentModel>[];
      for (String studentId in widget.selectedClass!.studentIds) {
        final doc = await _firebaseService.firestore
            .collection('schools')
            .doc(widget.teacher.schoolId)
            .collection('students')
            .doc(studentId)
            .get();
        if (doc.exists) {
          students.add(StudentModel.fromFirestore(doc));
        }
      }

      setState(() {
        _students = students;
        if (widget.preselectedStudentId != null &&
            students.any((s) => s.id == widget.preselectedStudentId)) {
          _selectAllStudents = false;
          _selectedStudentIds = [widget.preselectedStudentId!];
          _allocationType = AllocationType.byTitle;
        } else {
          _selectedStudentIds = students.map((s) => s.id).toList();
        }
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading students: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveAllocation() async {
    if (widget.selectedClass == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a class')),
      );
      return;
    }

    // Validation
    if (_allocationType == AllocationType.byTitle && _bookTitles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one book title')),
      );
      return;
    }

    if (!_selectAllStudents && _selectedStudentIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one student')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final allocation = AllocationModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        schoolId: widget.selectedClass!.schoolId,
        classId: widget.selectedClass!.id,
        teacherId: widget.teacher.id,
        studentIds: _selectAllStudents ? [] : _selectedStudentIds,
        type: _allocationType,
        cadence: _cadence,
        targetMinutes: int.tryParse(_minutesController.text) ?? 20,
        startDate: _startDate,
        endDate: _endDate,
        levelStart: _levelRangeStart,
        levelEnd: _levelRangeEnd,
        bookTitles: _bookTitles.isEmpty ? null : _bookTitles,
        isRecurring: _isRecurring,
        templateName: _templateName,
        createdAt: DateTime.now(),
        createdBy: widget.teacher.id,
      );

      await _firebaseService.firestore
          .collection('schools')
          .doc(widget.teacher.schoolId!)
          .collection('allocations')
          .doc(allocation.id)
          .set(allocation.toFirestore());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Allocation saved successfully')),
        );
        _resetForm();
      }
    } catch (e, stackTrace) {
      debugPrint('Error saving allocation: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save allocation: ${e.toString()}'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _resetForm() {
    setState(() {
      _allocationType = AllocationType.freeChoice;
      _cadence = AllocationCadence.weekly;
      _startDate = DateTime.now();
      _endDate = DateTime.now().add(const Duration(days: 7));
      if (widget.preselectedStudentId != null &&
          _students.any((s) => s.id == widget.preselectedStudentId)) {
        _selectAllStudents = false;
        _selectedStudentIds = [widget.preselectedStudentId!];
        _allocationType = AllocationType.byTitle;
      } else {
        _selectedStudentIds = _students.map((s) => s.id).toList();
        _selectAllStudents = true;
      }
      _levelRangeStart = null;
      _levelRangeEnd = null;
      _bookTitles.clear();
      _bookTitlesController.clear();
      _isRecurring = false;
      _templateName = null;
    });
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
          ),
        ),
        backgroundColor: AppColors.teacherPrimary,
        foregroundColor: AppColors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'New Allocation'),
            Tab(text: 'Active Allocations'),
          ],
          labelColor: AppColors.white,
          unselectedLabelColor: AppColors.white.withValues(alpha: 0.6),
          indicatorColor: AppColors.white,
          labelStyle: TeacherTypography.bodyMedium
              .copyWith(fontWeight: FontWeight.w600),
          unselectedLabelStyle: TeacherTypography.bodyMedium,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildNewAllocationView(),
          _buildActiveAllocationsView(),
        ],
      ),
    );
  }

  Widget _buildNewAllocationView() {
    if (widget.selectedClass == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.class_, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(
              'Please select a class from the dashboard',
              style: TeacherTypography.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Reading Type Card
          _buildCard(
            icon: Icons.book,
            title: 'Reading Type',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Info note
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.teacherPrimaryLight.withValues(alpha: 0.5),
                    borderRadius:
                        BorderRadius.circular(TeacherDimensions.radiusM),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: AppColors.teacherPrimary, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Reading levels and book selection system will be customized based on your school\'s requirements',
                          style: TeacherTypography.bodySmall.copyWith(
                            color: AppColors.teacherPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Allocation type selection
                _buildRadioOption(
                  title: 'Free Choice',
                  subtitle: 'Students can read any appropriate material',
                  value: AllocationType.freeChoice,
                  groupValue: _allocationType,
                  onChanged: (value) =>
                      setState(() => _allocationType = value!),
                ),
                _buildRadioOption(
                  title: 'By Reading Level',
                  subtitle: 'Specify a range of reading levels',
                  value: AllocationType.byLevel,
                  groupValue: _allocationType,
                  onChanged: (value) =>
                      setState(() => _allocationType = value!),
                ),
                _buildRadioOption(
                  title: 'Specific Books',
                  subtitle: 'List specific titles or materials',
                  value: AllocationType.byTitle,
                  groupValue: _allocationType,
                  onChanged: (value) =>
                      setState(() => _allocationType = value!),
                ),

                // Conditional fields based on type
                if (_allocationType == AllocationType.byLevel) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: InputDecoration(
                            labelText: 'Start Level',
                            hintText: 'e.g., A, 1, or custom',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  TeacherDimensions.radiusM),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  TeacherDimensions.radiusM),
                              borderSide:
                                  BorderSide(color: AppColors.teacherPrimary),
                            ),
                          ),
                          style: TeacherTypography.bodyMedium,
                          onChanged: (value) =>
                              setState(() => _levelRangeStart = value),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          decoration: InputDecoration(
                            labelText: 'End Level (optional)',
                            hintText: 'e.g., C, 5, or custom',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  TeacherDimensions.radiusM),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  TeacherDimensions.radiusM),
                              borderSide:
                                  BorderSide(color: AppColors.teacherPrimary),
                            ),
                          ),
                          style: TeacherTypography.bodyMedium,
                          onChanged: (value) =>
                              setState(() => _levelRangeEnd = value),
                        ),
                      ),
                    ],
                  ),
                ],

                if (_allocationType == AllocationType.byTitle) ...[
                  const SizedBox(height: 16),
                  ..._bookTitles.map((title) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius:
                              BorderRadius.circular(TeacherDimensions.radiusM),
                          boxShadow: TeacherDimensions.cardShadow,
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.menu_book,
                                color: AppColors.teacherPrimary, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(title,
                                    style: TeacherTypography.bodyMedium)),
                            IconButton(
                              icon: Icon(Icons.close,
                                  color: AppColors.textSecondary, size: 18),
                              onPressed: () =>
                                  setState(() => _bookTitles.remove(title)),
                            ),
                          ],
                        ),
                      )),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _bookTitlesController,
                          decoration: InputDecoration(
                            hintText: 'Enter book or material title',
                            prefixIcon: const Icon(Icons.add),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  TeacherDimensions.radiusM),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  TeacherDimensions.radiusM),
                              borderSide:
                                  BorderSide(color: AppColors.teacherPrimary),
                            ),
                          ),
                          style: TeacherTypography.bodyMedium,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (value) {
                            if (value.isNotEmpty) {
                              setState(() {
                                _bookTitles.add(value);
                                _bookTitlesController.clear();
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () {
                          if (_bookTitlesController.text.isNotEmpty) {
                            setState(() {
                              _bookTitles.add(_bookTitlesController.text);
                              _bookTitlesController.clear();
                            });
                          }
                        },
                        icon: const Icon(Icons.add_circle),
                        color: AppColors.teacherPrimary,
                        iconSize: 32,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Duration and Schedule Card
          _buildCard(
            icon: Icons.calendar_today,
            title: 'Schedule',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Cadence + minutes
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Frequency', style: TeacherTypography.bodySmall),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<AllocationCadence>(
                            initialValue: _cadence,
                            decoration: InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                    TeacherDimensions.radiusM),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                    TeacherDimensions.radiusM),
                                borderSide:
                                    BorderSide(color: AppColors.teacherPrimary),
                              ),
                            ),
                            style: TeacherTypography.bodyMedium
                                .copyWith(color: AppColors.charcoal),
                            items: AllocationCadence.values.map((cadence) {
                              return DropdownMenuItem(
                                value: cadence,
                                child: Text(_getCadenceLabel(cadence)),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() {
                                _cadence = value!;
                                _updateEndDate();
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Minutes Target',
                              style: TeacherTypography.bodySmall),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _minutesController,
                            decoration: InputDecoration(
                              isDense: true,
                              suffixText: 'min',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                    TeacherDimensions.radiusM),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                    TeacherDimensions.radiusM),
                                borderSide:
                                    BorderSide(color: AppColors.teacherPrimary),
                              ),
                            ),
                            style: TeacherTypography.bodyMedium,
                            keyboardType: TextInputType.number,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Date range
                Row(
                  children: [
                    Expanded(
                      child: _buildDatePicker(
                        label: 'Start Date',
                        date: _startDate,
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _startDate,
                            firstDate: DateTime.now(),
                            lastDate:
                                DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) {
                            setState(() {
                              _startDate = picked;
                              _updateEndDate();
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildDatePicker(
                        label: 'End Date',
                        date: _endDate,
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _endDate,
                            firstDate: _startDate,
                            lastDate:
                                DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) {
                            setState(() => _endDate = picked);
                          }
                        },
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Recurring option
                SwitchListTile(
                  title: Text('Recurring', style: TeacherTypography.bodyMedium),
                  subtitle: Text('Automatically repeat this allocation',
                      style: TeacherTypography.bodySmall),
                  value: _isRecurring,
                  activeTrackColor:
                      AppColors.teacherPrimary.withValues(alpha: 0.4),
                  activeThumbColor: AppColors.teacherPrimary,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (value) => setState(() => _isRecurring = value),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Student Selection Card
          _buildCard(
            icon: Icons.groups,
            title: 'Students',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildRadioOption(
                  title: 'Whole Class (${_students.length} students)',
                  value: true,
                  groupValue: _selectAllStudents,
                  onChanged: (value) {
                    setState(() {
                      _selectAllStudents = value!;
                      if (_selectAllStudents) {
                        _selectedStudentIds =
                            _students.map((s) => s.id).toList();
                      }
                    });
                  },
                ),
                _buildRadioOption(
                  title: 'Select Students',
                  value: false,
                  groupValue: _selectAllStudents,
                  onChanged: (value) =>
                      setState(() => _selectAllStudents = value!),
                ),
                if (!_selectAllStudents) ...[
                  const SizedBox(height: 8),
                  Container(
                    height: 200,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.divider),
                      borderRadius:
                          BorderRadius.circular(TeacherDimensions.radiusM),
                    ),
                    child: ListView.builder(
                      itemCount: _students.length,
                      itemBuilder: (context, index) {
                        final student = _students[index];
                        return CheckboxListTile(
                          title: Text(student.fullName,
                              style: TeacherTypography.bodyMedium),
                          subtitle: Text(
                              'Level: ${student.currentReadingLevel ?? "Not set"}',
                              style: TeacherTypography.bodySmall),
                          value: _selectedStudentIds.contains(student.id),
                          activeColor: AppColors.teacherPrimary,
                          onChanged: (value) {
                            setState(() {
                              if (value!) {
                                _selectedStudentIds.add(student.id);
                              } else {
                                _selectedStudentIds.remove(student.id);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Save as Template Option
          _buildCard(
            icon: Icons.save_alt,
            title: 'Template (Optional)',
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Save as template (e.g., "Monday Reading")',
                prefixIcon: Icon(Icons.bookmark_outline,
                    color: AppColors.teacherPrimary),
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(TeacherDimensions.radiusM),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(TeacherDimensions.radiusM),
                  borderSide: BorderSide(color: AppColors.teacherPrimary),
                ),
              ),
              style: TeacherTypography.bodyMedium,
              onChanged: (value) =>
                  setState(() => _templateName = value.isEmpty ? null : value),
            ),
          ),

          const SizedBox(height: 24),

          // Save Button
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _saveAllocation,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.teacherPrimary,
                foregroundColor: AppColors.white,
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(TeacherDimensions.radiusM),
                ),
                elevation: 0,
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.white))
                  : Text('Create Allocation',
                      style: TeacherTypography.buttonText),
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildActiveAllocationsView() {
    if (widget.selectedClass == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.class_, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(
              'Please select a class from the dashboard',
              style: TeacherTypography.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
            ),
          ],
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
          debugPrint('Error loading allocations: ${snapshot.error}');
          debugPrint('Error stack trace: ${snapshot.stackTrace}');
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline,
                    size: 64, color: AppColors.error),
                const SizedBox(height: 16),
                Text('Error loading allocations',
                    style: TeacherTypography.bodyLarge),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    snapshot.error.toString(),
                    style: TeacherTypography.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(
              child:
                  CircularProgressIndicator(color: AppColors.teacherPrimary));
        }

        // Filter allocations in code to avoid composite index requirement
        final now = DateTime.now();
        final allocations = snapshot.data!.docs
            .map((doc) => AllocationModel.fromFirestore(doc))
            .where((allocation) => allocation.endDate.isAfter(now))
            .toList();

        if (allocations.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.assignment_outlined,
                    size: 64, color: AppColors.textSecondary),
                const SizedBox(height: 16),
                Text(
                  'No active allocations',
                  style: TeacherTypography.bodyLarge
                      .copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => _tabController.animateTo(0),
                  child: Text(
                    'Create New Allocation',
                    style: TeacherTypography.bodyMedium.copyWith(
                      color: AppColors.teacherPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: allocations.length,
          itemBuilder: (context, index) {
            final allocation = allocations[index];
            return _AllocationCard(
              allocation: allocation,
              onEdit: () {
                // Handle edit
              },
              onDelete: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(TeacherDimensions.radiusL),
                    ),
                    title:
                        Text('Delete Allocation', style: TeacherTypography.h3),
                    content: Text(
                      'Are you sure you want to delete this allocation?',
                      style: TeacherTypography.bodyMedium,
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text('Cancel',
                            style: TeacherTypography.bodyMedium
                                .copyWith(color: AppColors.textSecondary)),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text('Delete',
                            style: TeacherTypography.bodyMedium
                                .copyWith(color: AppColors.error)),
                      ),
                    ],
                  ),
                );

                if (confirm == true) {
                  await _firebaseService.firestore
                      .collection('schools')
                      .doc(widget.teacher.schoolId!)
                      .collection('allocations')
                      .doc(allocation.id)
                      .update({'isActive': false});
                }
              },
            );
          },
        );
      },
    );
  }

  // -- Helpers --

  Widget _buildCard({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(TeacherDimensions.paddingXL),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
        boxShadow: TeacherDimensions.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.teacherPrimary, size: 22),
              const SizedBox(width: 8),
              Text(title, style: TeacherTypography.h3),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildRadioOption<T>({
    required String title,
    String? subtitle,
    required T value,
    required T groupValue,
    required ValueChanged<T?> onChanged,
  }) {
    return RadioListTile<T>(
      title: Text(title, style: TeacherTypography.bodyMedium),
      subtitle: subtitle != null
          ? Text(subtitle, style: TeacherTypography.bodySmall)
          : null,
      value: value,
      groupValue: groupValue,
      activeColor: AppColors.teacherPrimary,
      contentPadding: EdgeInsets.zero,
      onChanged: onChanged,
    );
  }

  Widget _buildDatePicker({
    required String label,
    required DateTime date,
    required VoidCallback onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TeacherTypography.bodySmall),
        const SizedBox(height: 8),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.divider),
              borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(DateFormat('MMM dd, yyyy').format(date),
                    style: TeacherTypography.bodyMedium),
                Icon(Icons.calendar_today,
                    size: 16, color: AppColors.teacherPrimary),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _getCadenceLabel(AllocationCadence cadence) {
    switch (cadence) {
      case AllocationCadence.daily:
        return 'Daily';
      case AllocationCadence.weekly:
        return 'Weekly';
      case AllocationCadence.fortnightly:
        return 'Fortnightly';
      case AllocationCadence.custom:
        return 'Custom';
    }
  }

  void _updateEndDate() {
    setState(() {
      switch (_cadence) {
        case AllocationCadence.daily:
          _endDate = _startDate.add(const Duration(days: 1));
          break;
        case AllocationCadence.weekly:
          _endDate = _startDate.add(const Duration(days: 7));
          break;
        case AllocationCadence.fortnightly:
          _endDate = _startDate.add(const Duration(days: 14));
          break;
        case AllocationCadence.custom:
          // Keep current end date
          break;
      }
    });
  }
}

class _AllocationCard extends StatelessWidget {
  final AllocationModel allocation;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _AllocationCard({
    required this.allocation,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final daysRemaining = allocation.endDate.difference(DateTime.now()).inDays;
    final isExpiring = daysRemaining <= 2;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
          boxShadow: TeacherDimensions.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getAllocationTitle(allocation),
                        style: TeacherTypography.bodyLarge
                            .copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${allocation.targetMinutes} minutes · ${_getCadenceLabel(allocation.cadence)}',
                        style: TeacherTypography.bodySmall,
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') {
                      onEdit();
                    } else if (value == 'delete') {
                      onDelete();
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Text('Edit'),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Date range
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isExpiring
                    ? AppColors.warning.withValues(alpha: 0.1)
                    : AppColors.background,
                borderRadius: BorderRadius.circular(TeacherDimensions.radiusS),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 16,
                    color: isExpiring
                        ? AppColors.warning
                        : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${DateFormat('MMM dd').format(allocation.startDate)} - ${DateFormat('MMM dd').format(allocation.endDate)}',
                    style: TeacherTypography.bodySmall.copyWith(
                      color: isExpiring
                          ? AppColors.warning
                          : AppColors.textSecondary,
                    ),
                  ),
                  if (isExpiring) ...[
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.warning,
                        borderRadius: BorderRadius.circular(
                            TeacherDimensions.radiusRound),
                      ),
                      child: Text(
                        'Expires soon',
                        style: TeacherTypography.caption.copyWith(
                          color: AppColors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Students
            Row(
              children: [
                Icon(Icons.groups, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Text(
                  allocation.isForWholeClass
                      ? 'Whole class'
                      : '${allocation.studentIds.length} students',
                  style: TeacherTypography.bodySmall,
                ),
              ],
            ),

            if (allocation.isRecurring) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.repeat, size: 16, color: AppColors.teacherPrimary),
                  const SizedBox(width: 8),
                  Text(
                    'Recurring',
                    style: TeacherTypography.bodySmall.copyWith(
                      color: AppColors.teacherPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _getAllocationTitle(AllocationModel allocation) {
    switch (allocation.type) {
      case AllocationType.byLevel:
        final levelText = allocation.levelEnd != null
            ? 'Level ${allocation.levelStart} - ${allocation.levelEnd}'
            : 'Level ${allocation.levelStart}';
        return levelText;
      case AllocationType.byTitle:
        if (allocation.bookTitles != null &&
            allocation.bookTitles!.isNotEmpty) {
          return allocation.bookTitles!.length == 1
              ? allocation.bookTitles!.first
              : '${allocation.bookTitles!.first} +${allocation.bookTitles!.length - 1} more';
        }
        return 'Specific Books';
      case AllocationType.freeChoice:
        return 'Free Choice Reading';
    }
  }

  String _getCadenceLabel(AllocationCadence cadence) {
    switch (cadence) {
      case AllocationCadence.daily:
        return 'Daily';
      case AllocationCadence.weekly:
        return 'Weekly';
      case AllocationCadence.fortnightly:
        return 'Fortnightly';
      case AllocationCadence.custom:
        return 'Custom';
    }
  }
}
