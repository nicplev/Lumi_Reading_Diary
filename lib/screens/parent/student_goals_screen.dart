import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/models/student_model.dart';
import '../../data/models/reading_goal_model.dart';
import '../../services/firebase_service.dart';
import '../../core/theme/app_colors.dart';

/// Screen for viewing and managing student reading goals
/// Allows students and parents to set targets and track progress
class StudentGoalsScreen extends StatefulWidget {
  final StudentModel student;

  const StudentGoalsScreen({
    super.key,
    required this.student,
  });

  @override
  State<StudentGoalsScreen> createState() => _StudentGoalsScreenState();
}

class _StudentGoalsScreenState extends State<StudentGoalsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  List<ReadingGoalModel> _activeGoals = [];
  List<ReadingGoalModel> _completedGoals = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadGoals();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reading Goals'),
        backgroundColor: AppColors.primaryBlue,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Active'),
            Tab(text: 'Completed'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildActiveGoalsTab(),
                _buildCompletedGoalsTab(),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateGoalDialog,
        backgroundColor: AppColors.primaryBlue,
        icon: const Icon(Icons.flag),
        label: const Text('New Goal'),
      ),
    );
  }

  Widget _buildActiveGoalsTab() {
    if (_activeGoals.isEmpty) {
      return _buildEmptyState(
        icon: Icons.flag_outlined,
        title: 'No Active Goals',
        message:
            'Set a reading goal to stay motivated and track your progress!',
        actionLabel: 'Create First Goal',
        onAction: _showCreateGoalDialog,
      );
    }

    return RefreshIndicator(
      onRefresh: _loadGoals,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _activeGoals.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _buildGoalsSummaryCard(),
            );
          }

          return _buildGoalCard(_activeGoals[index - 1]);
        },
      ),
    );
  }

  Widget _buildCompletedGoalsTab() {
    if (_completedGoals.isEmpty) {
      return _buildEmptyState(
        icon: Icons.emoji_events_outlined,
        title: 'No Completed Goals Yet',
        message:
            'Keep working on your active goals. Completed goals will appear here!',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadGoals,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _completedGoals.length,
        itemBuilder: (context, index) {
          return _buildGoalCard(_completedGoals[index], isCompleted: true);
        },
      ),
    );
  }

  Widget _buildGoalsSummaryCard() {
    final totalGoals = _activeGoals.length;
    final onTrackGoals =
        _activeGoals.where((g) => g.progressPercentage >= 0.5).length;
    final achievedGoals = _activeGoals.where((g) => g.isAchieved).length;

    return Card(
      elevation: 2,
      color: AppColors.primaryBlue.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.trending_up, color: AppColors.primaryBlue),
                const SizedBox(width: 8),
                Text(
                  'Goal Summary',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryItem('Total Goals', '$totalGoals',
                      Icons.flag, Colors.blue),
                ),
                Expanded(
                  child: _buildSummaryItem('On Track', '$onTrackGoals',
                      Icons.timeline, Colors.orange),
                ),
                Expanded(
                  child: _buildSummaryItem('Achieved', '$achievedGoals',
                      Icons.check_circle, Colors.green),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(
      String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(height: 8),
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildGoalCard(ReadingGoalModel goal, {bool isCompleted = false}) {
    final color = isCompleted
        ? Colors.green
        : goal.isAchieved
            ? Colors.green
            : goal.isExpired
                ? Colors.red
                : AppColors.primaryBlue;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _showGoalDetails(goal),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          goal.title,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        if (goal.description != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            goal.description!,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.grey[600],
                                    ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (goal.isAchieved)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.green),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle,
                              size: 16, color: Colors.green[700]),
                          const SizedBox(width: 4),
                          Text(
                            'Achieved!',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.green[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${goal.currentValue} / ${goal.targetValue} ${goal.valueUnit}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                            Text(
                              '${(goal.progressPercentage * 100).toStringAsFixed(0)}%',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: color,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: goal.progressPercentage,
                          backgroundColor: color.withOpacity(0.2),
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.calendar_today,
                          size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        'Ends ${DateFormat('MMM dd').format(goal.endDate)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                            ),
                      ),
                    ],
                  ),
                  if (!isCompleted && !goal.isAchieved)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: goal.daysRemaining <= 3
                            ? Colors.orange[50]
                            : Colors.blue[50],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${goal.daysRemaining} days left',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: goal.daysRemaining <= 3
                              ? Colors.orange[700]
                              : Colors.blue[700],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 24),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.grey[700],
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add),
                label: Text(actionLabel),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _loadGoals() async {
    setState(() => _isLoading = true);

    try {
      final firebaseService =
          Provider.of<FirebaseService>(context, listen: false);

      final snapshot = await firebaseService.firestore
          .collection('readingGoals')
          .where('studentId', isEqualTo: widget.student.id)
          .orderBy('createdAt', descending: true)
          .get();

      final goals = snapshot.docs
          .map((doc) => ReadingGoalModel.fromFirestore(doc))
          .toList();

      setState(() {
        _activeGoals = goals
            .where((g) =>
                g.status == GoalStatus.active && !g.isExpired ||
                (g.status == GoalStatus.active && g.isAchieved))
            .toList();

        _completedGoals =
            goals.where((g) => g.status == GoalStatus.completed).toList();

        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading goals: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showCreateGoalDialog() {
    showDialog(
      context: context,
      builder: (context) => _CreateGoalDialog(student: widget.student),
    ).then((created) {
      if (created == true) {
        _loadGoals();
      }
    });
  }

  void _showGoalDetails(ReadingGoalModel goal) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    if (goal.isAchieved)
                      Icon(Icons.emoji_events,
                          size: 32, color: Colors.amber[700])
                    else
                      Icon(Icons.flag, size: 32, color: AppColors.primaryBlue),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        goal.title,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                  ],
                ),
                if (goal.description != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    goal.description!,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.grey[700],
                        ),
                  ),
                ],
                const SizedBox(height: 24),
                _buildDetailRow(
                  'Goal Type',
                  goal.typeLabel,
                  Icons.category,
                ),
                _buildDetailRow(
                  'Target',
                  '${goal.targetValue} ${goal.valueUnit}',
                  Icons.my_location,
                ),
                _buildDetailRow(
                  'Current Progress',
                  '${goal.currentValue} ${goal.valueUnit}',
                  Icons.trending_up,
                ),
                _buildDetailRow(
                  'Progress',
                  '${(goal.progressPercentage * 100).toStringAsFixed(0)}%',
                  Icons.pie_chart,
                ),
                const Divider(height: 32),
                _buildDetailRow(
                  'Start Date',
                  DateFormat('MMM dd, yyyy').format(goal.startDate),
                  Icons.play_arrow,
                ),
                _buildDetailRow(
                  'End Date',
                  DateFormat('MMM dd, yyyy').format(goal.endDate),
                  Icons.flag,
                ),
                if (!goal.isAchieved && !goal.isExpired)
                  _buildDetailRow(
                    'Days Remaining',
                    '${goal.daysRemaining} days',
                    Icons.schedule,
                  ),
                if (goal.isAchieved && goal.completedAt != null)
                  _buildDetailRow(
                    'Completed On',
                    DateFormat('MMM dd, yyyy').format(goal.completedAt!),
                    Icons.check_circle,
                  ),
                if (goal.isAchieved && goal.rewardMessage != null) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.celebration,
                            color: Colors.green[700], size: 32),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            goal.rewardMessage!,
                            style:
                                Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      color: Colors.green[900],
                                      fontWeight: FontWeight.w500,
                                    ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                if (!goal.isAchieved && goal.status == GoalStatus.active)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _markGoalComplete(goal);
                      },
                      icon: const Icon(Icons.check),
                      label: const Text('Mark as Complete'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[600],
                      ),
                ),
                Text(
                  value,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _markGoalComplete(ReadingGoalModel goal) async {
    try {
      final firebaseService =
          Provider.of<FirebaseService>(context, listen: false);

      await firebaseService.firestore
          .collection('readingGoals')
          .doc(goal.id)
          .update({
        'status': 'completed',
        'completedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 Congratulations! Goal marked as complete!'),
          backgroundColor: Colors.green,
        ),
      );

      _loadGoals();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error completing goal: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

// Dialog for creating a new goal
class _CreateGoalDialog extends StatefulWidget {
  final StudentModel student;

  const _CreateGoalDialog({required this.student});

  @override
  State<_CreateGoalDialog> createState() => _CreateGoalDialogState();
}

class _CreateGoalDialogState extends State<_CreateGoalDialog> {
  GoalTemplate? _selectedTemplate;
  final _customTitleController = TextEditingController();
  final _customDescriptionController = TextEditingController();
  final _targetValueController = TextEditingController();
  int _durationDays = 7;

  @override
  void dispose() {
    _customTitleController.dispose();
    _customDescriptionController.dispose();
    _targetValueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.flag, color: AppColors.primaryBlue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Create Reading Goal',
                      style:
                          Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Choose a goal template:',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              ...GoalTemplate.templates.map((template) {
                return RadioListTile<GoalTemplate>(
                  title: Text(template.title),
                  subtitle: Text(template.description),
                  value: template,
                  groupValue: _selectedTemplate,
                  onChanged: (value) {
                    setState(() {
                      _selectedTemplate = value;
                      _targetValueController.text =
                          template.targetValue.toString();
                      _durationDays = template.durationDays;
                    });
                  },
                );
              }).toList(),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _selectedTemplate != null ? _createGoal : null,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                  ),
                  child: const Text('Create Goal'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createGoal() async {
    if (_selectedTemplate == null) return;

    try {
      final firebaseService =
          Provider.of<FirebaseService>(context, listen: false);

      final now = DateTime.now();
      final endDate = now.add(Duration(days: _durationDays));

      final goal = ReadingGoalModel(
        id: '',
        studentId: widget.student.id,
        schoolId: widget.student.schoolId,
        type: _selectedTemplate!.type,
        title: _selectedTemplate!.title,
        description: _selectedTemplate!.description,
        targetValue: _selectedTemplate!.targetValue,
        startDate: now,
        endDate: endDate,
        rewardMessage:
            'Amazing work! You achieved your goal! Keep up the great reading!',
        createdAt: now,
      );

      await firebaseService.firestore
          .collection('readingGoals')
          .add(goal.toFirestore());

      if (!mounted) return;

      Navigator.of(context).pop(true);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Goal created successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error creating goal: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
