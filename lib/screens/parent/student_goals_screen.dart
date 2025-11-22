import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/models/student_model.dart';
import '../../data/models/reading_goal_model.dart';
import '../../services/firebase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/lumi_text_styles.dart';
import '../../core/theme/lumi_spacing.dart';
import '../../core/theme/lumi_borders.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
import '../../core/widgets/lumi/lumi_card.dart';

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
        title: Text('Reading Goals', style: LumiTextStyles.h3()),
        backgroundColor: AppColors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.rosePink,
          unselectedLabelColor: AppColors.charcoal.withValues(alpha: 0.6),
          labelStyle: LumiTextStyles.bodyMedium(),
          indicatorColor: AppColors.rosePink,
          tabs: const [
            Tab(text: 'Active'),
            Tab(text: 'Completed'),
          ],
        ),
      ),
      backgroundColor: AppColors.offWhite,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.rosePink),
            ))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildActiveGoalsTab(),
                _buildCompletedGoalsTab(),
              ],
            ),
      floatingActionButton: LumiFab(
        onPressed: _showCreateGoalDialog,
        icon: Icons.flag,
        label: 'New Goal',
        isExtended: true,
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
      color: AppColors.rosePink,
      child: ListView.builder(
        padding: LumiPadding.allS,
        itemCount: _activeGoals.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: EdgeInsets.only(bottom: LumiSpacing.s),
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
      color: AppColors.rosePink,
      child: ListView.builder(
        padding: LumiPadding.allS,
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

    return LumiCard(
      isHighlighted: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.trending_up, color: AppColors.rosePink),
              LumiGap.horizontalXS,
              Text('Goal Summary', style: LumiTextStyles.h3()),
            ],
          ),
          LumiGap.s,
          Row(
            children: [
              Expanded(
                child: _buildSummaryItem(
                    'Total Goals', '$totalGoals', Icons.flag, AppColors.rosePink),
              ),
              Expanded(
                child: _buildSummaryItem('On Track', '$onTrackGoals',
                    Icons.timeline, AppColors.warmOrange),
              ),
              Expanded(
                child: _buildSummaryItem('Achieved', '$achievedGoals',
                    Icons.check_circle, AppColors.mintGreen),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(
      String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 32),
        LumiGap.xs,
        Text(
          value,
          style: LumiTextStyles.h2(color: color),
        ),
        Text(
          label,
          style: LumiTextStyles.bodySmall(
            color: AppColors.charcoal.withValues(alpha: 0.7),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildGoalCard(ReadingGoalModel goal, {bool isCompleted = false}) {
    final color = isCompleted
        ? AppColors.mintGreen
        : goal.isAchieved
            ? AppColors.mintGreen
            : goal.isExpired
                ? AppColors.error
                : AppColors.rosePink;

    return Padding(
      padding: EdgeInsets.only(bottom: LumiSpacing.listItemSpacing),
      child: LumiCard(
        padding: LumiPadding.allS,
        onTap: () => _showGoalDetails(goal),
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
                          style: LumiTextStyles.h3(),
                        ),
                        if (goal.description != null) ...[
                          LumiGap.xxs,
                          Text(
                            goal.description!,
                            style: LumiTextStyles.bodySmall(
                              color: AppColors.charcoal.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (goal.isAchieved)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: LumiSpacing.inputPaddingVertical,
                        vertical: LumiSpacing.elementSpacing - 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.mintGreen.withValues(alpha: 0.1),
                        borderRadius: LumiBorders.medium,
                        border: Border.all(color: AppColors.mintGreen, width: 2),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle,
                              size: 16, color: AppColors.mintGreen),
                          LumiGap.horizontalXXS,
                          Text(
                            'Achieved!',
                            style: LumiTextStyles.label(color: AppColors.mintGreen),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              LumiGap.s,
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
                              style: LumiTextStyles.bodyMedium(),
                            ),
                            Text(
                              '${(goal.progressPercentage * 100).toStringAsFixed(0)}%',
                              style: LumiTextStyles.bodyMedium(color: color),
                            ),
                          ],
                        ),
                        LumiGap.xs,
                        LinearProgressIndicator(
                          value: goal.progressPercentage,
                          backgroundColor: color.withValues(alpha: 0.2),
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                          borderRadius: LumiBorders.small,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              LumiGap.xs,
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.calendar_today,
                          size: 14, color: AppColors.charcoal.withValues(alpha: 0.6)),
                      LumiGap.horizontalXXS,
                      Text(
                        'Ends ${DateFormat('MMM dd').format(goal.endDate)}',
                        style: LumiTextStyles.bodySmall(
                          color: AppColors.charcoal.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                  if (!isCompleted && !goal.isAchieved)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: LumiSpacing.xs,
                        vertical: LumiSpacing.xxs,
                      ),
                      decoration: BoxDecoration(
                        color: goal.daysRemaining <= 3
                            ? AppColors.warmOrange.withValues(alpha: 0.1)
                            : AppColors.rosePink.withValues(alpha: 0.1),
                        borderRadius: LumiBorders.medium,
                      ),
                      child: Text(
                        '${goal.daysRemaining} days left',
                        style: LumiTextStyles.caption(
                          color: goal.daysRemaining <= 3
                              ? AppColors.warmOrange
                              : AppColors.rosePink,
                        ),
                      ),
                    ),
                ],
              ),
            ],
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
        padding: LumiPadding.allL,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 80, color: AppColors.charcoal.withValues(alpha: 0.3)),
            LumiGap.m,
            Text(
              title,
              style: LumiTextStyles.h2(
                color: AppColors.charcoal.withValues(alpha: 0.7),
              ),
            ),
            LumiGap.xs,
            Text(
              message,
              style: LumiTextStyles.body(
                color: AppColors.charcoal.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              LumiGap.m,
              LumiPrimaryButton(
                onPressed: onAction,
                icon: Icons.add,
                text: actionLabel,
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
          backgroundColor: AppColors.error,
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
                      color: AppColors.charcoal.withValues(alpha: 0.2),
                      borderRadius: LumiBorders.custom(2),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    if (goal.isAchieved)
                      Icon(Icons.emoji_events,
                          size: 32, color: AppColors.softYellow)
                    else
                      Icon(Icons.flag, size: 32, color: AppColors.rosePink),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        goal.title,
                        style: LumiTextStyles.h2(),
                      ),
                    ),
                  ],
                ),
                if (goal.description != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    goal.description!,
                    style: LumiTextStyles.bodyLarge(
                      color: AppColors.charcoal.withValues(alpha: 0.7),
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
                    padding: LumiPadding.allS,
                    decoration: BoxDecoration(
                      color: AppColors.mintGreen.withValues(alpha: 0.1),
                      borderRadius: LumiBorders.medium,
                      border: Border.all(color: AppColors.mintGreen, width: 2),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.celebration,
                            color: AppColors.mintGreen, size: 32),
                        LumiGap.horizontalXS,
                        Expanded(
                          child: Text(
                            goal.rewardMessage!,
                            style: LumiTextStyles.bodyLarge(
                              color: AppColors.success,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                if (!goal.isAchieved && goal.status == GoalStatus.active)
                  LumiSecondaryButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _markGoalComplete(goal);
                    },
                    icon: Icons.check,
                    text: 'Mark as Complete',
                    isFullWidth: true,
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
      padding: EdgeInsets.only(bottom: LumiSpacing.inputPaddingVertical),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.charcoal.withValues(alpha: 0.6)),
          LumiGap.horizontalXS,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: LumiTextStyles.bodySmall(
                    color: AppColors.charcoal.withValues(alpha: 0.7),
                  ),
                ),
                Text(
                  value,
                  style: LumiTextStyles.bodyLarge(),
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
          backgroundColor: AppColors.mintGreen,
        ),
      );

      _loadGoals();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error completing goal: $e'),
          backgroundColor: AppColors.error,
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
      shape: LumiBorders.shapeLarge,
      child: SingleChildScrollView(
        child: Padding(
          padding: LumiPadding.allM,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.flag, color: AppColors.rosePink),
                  LumiGap.horizontalXS,
                  Expanded(
                    child: Text(
                      'Create Reading Goal',
                      style: LumiTextStyles.h2(),
                    ),
                  ),
                  LumiIconButton(
                    icon: Icons.close,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              LumiGap.m,
              Text(
                'Choose a goal template:',
                style: LumiTextStyles.h3(),
              ),
              LumiGap.xs,
              ...GoalTemplate.templates.map((template) {
                return RadioListTile<GoalTemplate>(
                  title: Text(template.title, style: LumiTextStyles.bodyMedium()),
                  subtitle: Text(template.description, style: LumiTextStyles.bodySmall()),
                  value: template,
                  groupValue: _selectedTemplate,
                  activeColor: AppColors.rosePink,
                  onChanged: (value) {
                    setState(() {
                      _selectedTemplate = value;
                      _targetValueController.text =
                          template.targetValue.toString();
                      _durationDays = template.durationDays;
                    });
                  },
                );
              }),
              LumiGap.m,
              LumiPrimaryButton(
                onPressed: _selectedTemplate != null ? _createGoal : null,
                text: 'Create Goal',
                isFullWidth: true,
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
          backgroundColor: AppColors.mintGreen,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error creating goal: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }
}
