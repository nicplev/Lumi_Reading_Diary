import 'package:flutter/material.dart';
import '../../services/firebase_service.dart';
import '../../data/models/reading_group_model.dart';
import '../../data/models/student_model.dart';
import '../../core/widgets/glass/glass_container.dart';
import '../../core/widgets/glass/glass_button.dart';

/// Teacher screen for managing reading groups
///
/// Features:
/// - View all groups in class
/// - Create new groups (custom or from templates)
/// - Edit group details and goals
/// - Assign/remove students
/// - View group performance
/// - Delete groups
class ReadingGroupsScreen extends StatefulWidget {
  final String teacherId;
  final String schoolId;
  final String classId;

  const ReadingGroupsScreen({
    super.key,
    required this.teacherId,
    required this.schoolId,
    required this.classId,
  });

  @override
  State<ReadingGroupsScreen> createState() => _ReadingGroupsScreenState();
}

class _ReadingGroupsScreenState extends State<ReadingGroupsScreen> {
  final _firebaseService = FirebaseService.instance;

  List<ReadingGroupModel> _groups = [];
  List<StudentModel> _students = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // Load groups
      final groupsSnapshot = await _firebaseService.firestore
          .collection('schools')
          .doc(widget.schoolId)
          .collection('readingGroups')
          .where('classId', isEqualTo: widget.classId)
          .get();

      final groups = groupsSnapshot.docs
          .map((doc) => ReadingGroupModel.fromFirestore(doc))
          .toList();

      // Load students in class
      final studentsSnapshot = await _firebaseService.firestore
          .collection('schools')
          .doc(widget.schoolId)
          .collection('students')
          .where('classId', isEqualTo: widget.classId)
          .get();

      final students = studentsSnapshot.docs
          .map((doc) => StudentModel.fromFirestore(doc))
          .toList();

      setState(() {
        _groups = groups;
        _students = students;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading groups: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _showCreateGroupDialog() async {
    await showDialog(
      context: context,
      builder: (context) => CreateGroupDialog(
        schoolId: widget.schoolId,
        classId: widget.classId,
        onGroupCreated: _loadData,
      ),
    );
  }

  Future<void> _showEditGroupDialog(ReadingGroupModel group) async {
    await showDialog(
      context: context,
      builder: (context) => EditGroupDialog(
        group: group,
        schoolId: widget.schoolId,
        students: _students,
        onGroupUpdated: _loadData,
      ),
    );
  }

  Future<void> _deleteGroup(ReadingGroupModel group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Group?'),
        content: Text('Are you sure you want to delete "${group.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _firebaseService.firestore
            .collection('schools')
            .doc(widget.schoolId)
            .collection('readingGroups')
            .doc(group.id)
            .delete();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Group deleted')),
          );
        }

        _loadData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting group: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Reading Groups'),
        backgroundColor: const Color(0xFF1976D2),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showCreateGroupDialog,
            tooltip: 'Create Group',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: _groups.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _groups.length,
                      itemBuilder: (context, index) {
                        final group = _groups[index];
                        return _buildGroupCard(group);
                      },
                    ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateGroupDialog,
        backgroundColor: const Color(0xFF1976D2),
        icon: const Icon(Icons.add),
        label: const Text('Create Group'),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.groups, size: 80, color: Color(0xFF9E9E9E)),
          const SizedBox(height: 16),
          const Text(
            'No reading groups yet',
            style: TextStyle(fontSize: 20, color: Color(0xFF616161)),
          ),
          const SizedBox(height: 8),
          const Text(
            'Create groups to organize students',
            style: TextStyle(fontSize: 14, color: Color(0xFF9E9E9E)),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _showCreateGroupDialog,
            icon: const Icon(Icons.add),
            label: const Text('Create Your First Group'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1976D2),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupCard(ReadingGroupModel group) {
    final color = Color(int.parse(group.color.replaceFirst('#', '0xFF')));
    final members = _students.where((s) => group.studentIds.contains(s.id)).toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: () => _showEditGroupDialog(group),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _getGroupIcon(group.type),
                      color: color,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (group.description != null)
                          Text(
                            group.description!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF616161),
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Color(0xFF9E9E9E)),
                    onPressed: () => _deleteGroup(group),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildGroupStat(
                      '👥 Members',
                      '${group.memberCount}',
                    ),
                  ),
                  Expanded(
                    child: _buildGroupStat(
                      '⏱️ Weekly',
                      '${group.stats.weeklyMinutes}/${group.goals.targetMinutesPerWeek} min',
                    ),
                  ),
                  Expanded(
                    child: _buildGroupStat(
                      '📚 Monthly',
                      '${group.stats.monthlyBooks}/${group.goals.targetBooksPerMonth} books',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: group.goalsProgressPercentage,
                backgroundColor: const Color(0xFFE0E0E0),
                valueColor: AlwaysStoppedAnimation(color),
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 8),
              Text(
                '${(group.goalsProgressPercentage * 100).round()}% of weekly goal',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF616161),
                ),
              ),
              if (members.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: members.take(5).map((student) {
                    return Chip(
                      label: Text(
                        '${student.firstName} ${student.lastName[0]}.',
                        style: const TextStyle(fontSize: 11),
                      ),
                      backgroundColor: color.withOpacity(0.1),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    );
                  }).toList(),
                ),
                if (members.length > 5)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '+${members.length - 5} more',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF9E9E9E),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGroupStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF9E9E9E),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1976D2),
          ),
        ),
      ],
    );
  }

  IconData _getGroupIcon(GroupType type) {
    switch (type) {
      case GroupType.ability:
        return Icons.school;
      case GroupType.interest:
        return Icons.favorite;
      case GroupType.project:
        return Icons.menu_book;
      case GroupType.mixed:
        return Icons.groups;
    }
  }
}

// Create Group Dialog
class CreateGroupDialog extends StatefulWidget {
  final String schoolId;
  final String classId;
  final VoidCallback onGroupCreated;

  const CreateGroupDialog({
    super.key,
    required this.schoolId,
    required this.classId,
    required this.onGroupCreated,
  });

  @override
  State<CreateGroupDialog> createState() => _CreateGroupDialogState();
}

class _CreateGroupDialogState extends State<CreateGroupDialog> {
  final _firebaseService = FirebaseService.instance;
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  int? _selectedTemplate;
  GroupType _type = GroupType.ability;
  String _color = '#1976D2';

  bool _isCreating = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _createGroup() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a group name')),
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      final group = ReadingGroupModel(
        id: '',
        schoolId: widget.schoolId,
        classId: widget.classId,
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        type: _type,
        color: _color,
        studentIds: [],
        goals: GroupGoals(),
        stats: GroupStats(),
        createdAt: DateTime.now(),
      );

      await _firebaseService.firestore
          .collection('schools')
          .doc(widget.schoolId)
          .collection('readingGroups')
          .add(group.toFirestore());

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Group created successfully!')),
        );
        widget.onGroupCreated();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating group: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  void _useTemplate(int index) {
    final template = GroupTemplates.templates[index];
    _nameController.text = template['name'] as String;
    _descriptionController.text = template['description'] as String;
    _type = GroupType.values.firstWhere((e) => e.name == template['type']);
    _color = template['color'] as String;
    setState(() => _selectedTemplate = index);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Create Reading Group',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              // Templates
              const Text('Quick Templates', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: List.generate(GroupTemplates.templates.length, (index) {
                  final template = GroupTemplates.templates[index];
                  final isSelected = _selectedTemplate == index;

                  return ChoiceChip(
                    label: Text(template['name'] as String),
                    selected: isSelected,
                    onSelected: (selected) => _useTemplate(index),
                  );
                }),
              ),
              const SizedBox(height: 16),

              // Group Name
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Group Name *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              // Description
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 24),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _isCreating ? null : _createGroup,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1976D2),
                      foregroundColor: Colors.white,
                    ),
                    child: _isCreating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Create'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Edit Group Dialog (simplified - full implementation would include student assignment)
class EditGroupDialog extends StatelessWidget {
  final ReadingGroupModel group;
  final String schoolId;
  final List<StudentModel> students;
  final VoidCallback onGroupUpdated;

  const EditGroupDialog({
    super.key,
    required this.group,
    required this.schoolId,
    required this.students,
    required this.onGroupUpdated,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Edit ${group.name}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text('Full edit functionality available in production version'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
