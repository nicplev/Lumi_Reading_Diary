import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/user_model.dart';
import '../../data/models/class_model.dart';
import '../../data/models/student_model.dart';
import '../../data/models/allocation_model.dart';
import '../../services/firebase_service.dart';

class AllocationScreen extends StatefulWidget {
  final UserModel teacher;
  final ClassModel? selectedClass;

  const AllocationScreen({
    super.key,
    required this.teacher,
    this.selectedClass,
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
        _selectedStudentIds = students.map((s) => s.id).toList();
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save allocation')),
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
      _selectedStudentIds = _students.map((s) => s.id).toList();
      _selectAllStudents = true;
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
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        title: const Text('Reading Allocation'),
        backgroundColor: AppColors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'New Allocation'),
            Tab(text: 'Active Allocations'),
          ],
          labelColor: AppColors.primaryBlue,
          unselectedLabelColor: AppColors.gray,
          indicatorColor: AppColors.primaryBlue,
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
      return const Center(
        child: Text('Please select a class from the dashboard'),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Reading Type Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.book, color: AppColors.secondaryPurple),
                      const SizedBox(width: 8),
                      Text(
                        'Reading Type',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Note about flexible system
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.info.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            color: AppColors.info, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Reading levels and book selection system will be customized based on your school\'s requirements',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppColors.info,
                                    ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Allocation type selection
                  Column(
                    children: [
                      RadioListTile<AllocationType>(
                        title: const Text('Free Choice'),
                        subtitle: const Text(
                            'Students can read any appropriate material'),
                        value: AllocationType.freeChoice,
                        groupValue: _allocationType,
                        onChanged: (value) {
                          setState(() {
                            _allocationType = value!;
                          });
                        },
                      ),
                      RadioListTile<AllocationType>(
                        title: const Text('By Reading Level'),
                        subtitle:
                            const Text('Specify a range of reading levels'),
                        value: AllocationType.byLevel,
                        groupValue: _allocationType,
                        onChanged: (value) {
                          setState(() {
                            _allocationType = value!;
                          });
                        },
                      ),
                      RadioListTile<AllocationType>(
                        title: const Text('Specific Books'),
                        subtitle:
                            const Text('List specific titles or materials'),
                        value: AllocationType.byTitle,
                        groupValue: _allocationType,
                        onChanged: (value) {
                          setState(() {
                            _allocationType = value!;
                          });
                        },
                      ),
                    ],
                  ),

                  // Conditional fields based on type
                  if (_allocationType == AllocationType.byLevel) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                              labelText: 'Start Level',
                              hintText: 'e.g., A, 1, or custom',
                            ),
                            onChanged: (value) {
                              setState(() {
                                _levelRangeStart = value;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                              labelText: 'End Level (optional)',
                              hintText: 'e.g., C, 5, or custom',
                            ),
                            onChanged: (value) {
                              setState(() {
                                _levelRangeEnd = value;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ],

                  if (_allocationType == AllocationType.byTitle) ...[
                    const SizedBox(height: 16),
                    ..._bookTitles.map((title) => Card(
                          color: AppColors.offWhite,
                          child: ListTile(
                            leading: const Icon(Icons.menu_book,
                                color: AppColors.secondaryPurple),
                            title: Text(title),
                            trailing: IconButton(
                              icon: const Icon(Icons.close,
                                  color: AppColors.gray),
                              onPressed: () {
                                setState(() {
                                  _bookTitles.remove(title);
                                });
                              },
                            ),
                          ),
                        )),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _bookTitlesController,
                            decoration: const InputDecoration(
                              hintText: 'Enter book or material title',
                              prefixIcon: Icon(Icons.add),
                            ),
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
                          color: AppColors.primaryBlue,
                          iconSize: 32,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Duration and Schedule Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.calendar_today,
                          color: AppColors.primaryBlue),
                      const SizedBox(width: 8),
                      Text(
                        'Schedule',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Cadence
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Frequency'),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<AllocationCadence>(
                              initialValue: _cadence,
                              decoration: const InputDecoration(
                                isDense: true,
                              ),
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
                            const Text('Minutes Target'),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _minutesController,
                              decoration: const InputDecoration(
                                isDense: true,
                                suffixText: 'min',
                              ),
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Start Date'),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _startDate,
                                  firstDate: DateTime.now(),
                                  lastDate: DateTime.now()
                                      .add(const Duration(days: 365)),
                                );
                                if (picked != null) {
                                  setState(() {
                                    _startDate = picked;
                                    _updateEndDate();
                                  });
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  border:
                                      Border.all(color: AppColors.lightGray),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(DateFormat('MMM dd, yyyy')
                                        .format(_startDate)),
                                    const Icon(Icons.calendar_today, size: 16),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('End Date'),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _endDate,
                                  firstDate: _startDate,
                                  lastDate: DateTime.now()
                                      .add(const Duration(days: 365)),
                                );
                                if (picked != null) {
                                  setState(() {
                                    _endDate = picked;
                                  });
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  border:
                                      Border.all(color: AppColors.lightGray),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(DateFormat('MMM dd, yyyy')
                                        .format(_endDate)),
                                    const Icon(Icons.calendar_today, size: 16),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Recurring option
                  SwitchListTile(
                    title: const Text('Recurring'),
                    subtitle:
                        const Text('Automatically repeat this allocation'),
                    value: _isRecurring,
                    onChanged: (value) {
                      setState(() {
                        _isRecurring = value;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Student Selection Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.groups, color: AppColors.secondaryGreen),
                      const SizedBox(width: 8),
                      Text(
                        'Students',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  RadioListTile<bool>(
                    title: Text('Whole Class (${_students.length} students)'),
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
                  RadioListTile<bool>(
                    title: const Text('Select Students'),
                    value: false,
                    groupValue: _selectAllStudents,
                    onChanged: (value) {
                      setState(() {
                        _selectAllStudents = value!;
                      });
                    },
                  ),
                  if (!_selectAllStudents) ...[
                    const SizedBox(height: 8),
                    Container(
                      height: 200,
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.lightGray),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.builder(
                        itemCount: _students.length,
                        itemBuilder: (context, index) {
                          final student = _students[index];
                          return CheckboxListTile(
                            title: Text(student.fullName),
                            subtitle: Text(
                                'Level: ${student.currentReadingLevel ?? "Not set"}'),
                            value: _selectedStudentIds.contains(student.id),
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
          ),

          const SizedBox(height: 16),

          // Save as Template Option
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.save_alt,
                          color: AppColors.secondaryYellow),
                      const SizedBox(width: 8),
                      Text(
                        'Template (Optional)',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    decoration: const InputDecoration(
                      hintText: 'Save as template (e.g., "Monday Reading")',
                      prefixIcon: Icon(Icons.bookmark_outline),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _templateName = value.isEmpty ? null : value;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Save Button
          ElevatedButton(
            onPressed: _isLoading ? null : _saveAllocation,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(AppColors.white),
                    ),
                  )
                : const Text('Create Allocation'),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildActiveAllocationsView() {
    if (widget.selectedClass == null) {
      return const Center(
        child: Text('Please select a class from the dashboard'),
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
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: AppColors.error),
                const SizedBox(height: 16),
                Text('Error loading allocations', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  snapshot.error.toString(),
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
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
                Icon(
                  Icons.assignment_outlined,
                  size: 64,
                  color: AppColors.gray.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  'No active allocations',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.gray,
                      ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    _tabController.animateTo(0);
                  },
                  child: const Text('Create New Allocation'),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
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
                    title: const Text('Delete Allocation'),
                    content: const Text(
                      'Are you sure you want to delete this allocation?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Delete'),
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

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${allocation.targetMinutes} minutes · ${_getCadenceLabel(allocation.cadence)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.gray,
                            ),
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
                    : AppColors.lightGray.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 16,
                    color: isExpiring ? AppColors.warning : AppColors.gray,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${DateFormat('MMM dd').format(allocation.startDate)} - ${DateFormat('MMM dd').format(allocation.endDate)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              isExpiring ? AppColors.warning : AppColors.gray,
                        ),
                  ),
                  if (isExpiring) ...[
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.warning,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Expires soon',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
                const Icon(Icons.groups, size: 16, color: AppColors.gray),
                const SizedBox(width: 8),
                Text(
                  allocation.isForWholeClass
                      ? 'Whole class'
                      : '${allocation.studentIds.length} students',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.gray,
                      ),
                ),
              ],
            ),

            if (allocation.isRecurring) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.repeat,
                    size: 16,
                    color: AppColors.secondaryGreen,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Recurring',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.secondaryGreen,
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
