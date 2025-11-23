import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lumi_reading_tracker/data/models/achievement_model.dart';
import 'package:lumi_reading_tracker/data/models/student_model.dart';
import 'package:lumi_reading_tracker/core/theme/app_colors.dart';
import 'package:lumi_reading_tracker/core/theme/lumi_text_styles.dart';
import 'package:lumi_reading_tracker/core/theme/lumi_spacing.dart';
import 'package:lumi_reading_tracker/core/theme/lumi_borders.dart';
import 'package:lumi_reading_tracker/core/widgets/lumi/lumi_buttons.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Achievements screen showing earned and locked achievements
class AchievementsScreen extends StatefulWidget {
  final String studentId;
  final String schoolId;

  const AchievementsScreen({
    super.key,
    required this.studentId,
    required this.schoolId,
  });

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  AchievementCategory? _selectedCategory;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      body: SafeArea(
        child: Column(
          children: [
            // App bar
            _buildAppBar(),

            // Category filter
            _buildCategoryFilter(),

            // Tabs (Earned / All)
            _buildTabs(),

            // Achievement list
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildEarnedAchievements(),
                  _buildAllAchievements(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: LumiPadding.allS,
      child: Row(
        children: [
          LumiIconButton(
            icon: Icons.arrow_back,
            onPressed: () => Navigator.pop(context),
          ),
          LumiGap.horizontalXS,
          Text(
            '🏆 Achievements',
            style: LumiTextStyles.h2(),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilter() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: LumiPadding.horizontalS,
      child: Row(
        children: [
          _buildCategoryChip(
            'All',
            null,
            _selectedCategory == null,
          ),
          LumiGap.horizontalXS,
          ...AchievementCategory.values.map((category) {
            return Padding(
              padding: EdgeInsets.only(right: LumiSpacing.xs),
              child: _buildCategoryChip(
                category.displayName,
                category,
                _selectedCategory == category,
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(String label, AchievementCategory? category, bool selected) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (value) {
        setState(() {
          _selectedCategory = selected ? null : category;
        });
      },
      backgroundColor: AppColors.white,
      selectedColor: AppColors.skyBlue,
      checkmarkColor: AppColors.rosePink,
      labelStyle: LumiTextStyles.label(
        color: selected ? AppColors.rosePink : AppColors.charcoal,
      ).copyWith(
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      ),
      side: BorderSide(
        color: selected
            ? AppColors.rosePink
            : AppColors.charcoal.withValues(alpha: 0.3),
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      margin: LumiPadding.allS,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: LumiBorders.large,
        border: Border.all(
          color: AppColors.charcoal.withValues(alpha: 0.2),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: AppColors.skyBlue,
          borderRadius: LumiBorders.large,
        ),
        labelColor: AppColors.rosePink,
        labelStyle: LumiTextStyles.label(),
        unselectedLabelColor: AppColors.charcoal.withValues(alpha: 0.6),
        tabs: const [
          Tab(text: 'Earned'),
          Tab(text: 'All Achievements'),
        ],
      ),
    );
  }

  Widget _buildEarnedAchievements() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolId)
          .collection('students')
          .doc(widget.studentId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildErrorState(snapshot.error.toString());
        }

        if (!snapshot.hasData) {
          return _buildLoadingState();
        }

        final studentData = snapshot.data!.data() as Map<String, dynamic>?;
        if (studentData == null) {
          return _buildEmptyState('Student data not found');
        }

        final achievementsData =
            studentData['achievements'] as List<dynamic>? ?? [];

        if (achievementsData.isEmpty) {
          return _buildEmptyState('No achievements yet!\\nKeep reading to unlock them! 📚');
        }

        final achievements = achievementsData
            .map((data) =>
                AchievementModel.fromMap(Map<String, dynamic>.from(data)))
            .toList();

        // Filter by category if selected
        final filteredAchievements = _selectedCategory == null
            ? achievements
            : achievements
                .where((a) => a.category == _selectedCategory)
                .toList();

        if (filteredAchievements.isEmpty) {
          return _buildEmptyState('No achievements in this category yet!');
        }

        // Sort by earned date (newest first)
        filteredAchievements.sort((a, b) => b.earnedAt.compareTo(a.earnedAt));

        return ListView.builder(
          padding: EdgeInsets.symmetric(vertical: LumiSpacing.xs),
          itemCount: filteredAchievements.length,
          itemBuilder: (context, index) {
            return _buildAchievementCard(
              filteredAchievements[index],
              animate: index < 5,
            );
          },
        );
      },
    );
  }

  Widget _buildAllAchievements() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolId)
          .collection('students')
          .doc(widget.studentId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildErrorState(snapshot.error.toString());
        }

        if (!snapshot.hasData) {
          return _buildLoadingState();
        }

        final student = StudentModel.fromFirestore(snapshot.data!);
        final earnedAchievementIds = (snapshot.data!.data()
                    as Map<String, dynamic>?)?['achievements']
            ?.map<String>((a) => a['id'] as String)
            .toList() ??
        [];

        // Get all templates
        var allTemplates = AchievementTemplates.allTemplates;

        // Filter by category if selected
        if (_selectedCategory != null) {
          allTemplates = allTemplates
              .where((t) => t['category'] == _selectedCategory.toString().split('.').last)
              .toList();
        }

        return GridView.builder(
          padding: LumiPadding.allS,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: LumiSpacing.listItemSpacing,
            mainAxisSpacing: LumiSpacing.listItemSpacing,
            childAspectRatio: 0.8,
          ),
          itemCount: allTemplates.length,
          itemBuilder: (context, index) {
            final template = allTemplates[index];
            final id = template['id'] as String;
            final isEarned = earnedAchievementIds.contains(id);

            // Create achievement model (mock for locked ones)
            final achievement = AchievementModel(
              id: id,
              name: template['name'] as String,
              description: template['description'] as String,
              icon: template['icon'] as String,
              category: AchievementCategory.values.firstWhere(
                (e) =>
                    e.toString() ==
                    'AchievementCategory.${template['category']}',
              ),
              rarity: AchievementRarity.values.firstWhere(
                (e) =>
                    e.toString() ==
                    'AchievementRarity.${template['rarity']}',
              ),
              requiredValue: template['requiredValue'] as int,
              requirementType: template['requirementType'] as String,
              earnedAt: DateTime.now(), // Placeholder
            );

            return GlassAchievementBadge(
              achievement: achievement,
              locked: !isEarned,
              onTap: () => _showAchievementProgress(
                achievement,
                student,
                isEarned,
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            color: AppColors.rosePink,
          ),
          LumiGap.s,
          Text(
            'Loading achievements...',
            style: LumiTextStyles.body(
              color: AppColors.charcoal.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 64,
            color: AppColors.error,
          ),
          LumiGap.s,
          Text(
            'Error loading achievements',
            style: LumiTextStyles.h3(
              color: AppColors.charcoal,
            ),
          ),
          LumiGap.xs,
          Text(
            error,
            style: LumiTextStyles.bodySmall(
              color: AppColors.charcoal.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '🏆',
            style: LumiTextStyles.display().copyWith(fontSize: 64),
          )
              .animate(onPlay: (controller) => controller.repeat())
              .shimmer(duration: 2000.ms)
              .shake(hz: 2, rotation: 0.05),
          LumiGap.s,
          Text(
            message,
            style: LumiTextStyles.h3(
              color: AppColors.charcoal,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildAchievementCard(AchievementModel achievement, {bool animate = false}) {
    final isEarned = achievement.earnedAt.year > 1970; // Check if earned (default DateTime is epoch)

    return GestureDetector(
      onTap: () => _showAchievementDetail(achievement),
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: LumiSpacing.s, vertical: LumiSpacing.xs),
        padding: LumiPadding.allM,
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: LumiBorders.large,
          border: Border.all(
            color: isEarned ? AppColors.rosePink : AppColors.charcoal.withValues(alpha: 0.1),
            width: isEarned ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isEarned
                ? AppColors.rosePink.withValues(alpha: 0.1)
                : AppColors.charcoal.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Icon/Emoji
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: isEarned
                  ? AppColors.rosePink.withValues(alpha: 0.1)
                  : AppColors.charcoal.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  achievement.icon,
                  style: const TextStyle(fontSize: 32),
                ),
              ),
            ),
            SizedBox(width: LumiSpacing.s),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    achievement.name,
                    style: LumiTextStyles.h3(
                      color: isEarned ? AppColors.charcoal : AppColors.charcoal.withValues(alpha: 0.5),
                    ),
                  ),
                  SizedBox(height: LumiSpacing.xxs),
                  Text(
                    achievement.description,
                    style: LumiTextStyles.bodySmall(
                      color: AppColors.charcoal.withValues(alpha: 0.7),
                    ),
                  ),
                  if (isEarned) ...[
                    SizedBox(height: LumiSpacing.xxs),
                    Text(
                      'Earned ${_formatDate(achievement.earnedAt)}',
                      style: LumiTextStyles.label(color: AppColors.rosePink),
                    ),
                  ],
                ],
              ),
            ),
            // Check icon if earned
            if (isEarned)
              const Icon(
                Icons.check_circle,
                color: AppColors.rosePink,
                size: 24,
              ),
          ],
        ),
      ),
    ).animate(
      effects: animate ? [
        FadeEffect(duration: 300.ms, delay: (50 * (achievement.id.hashCode % 5)).ms),
        SlideEffect(begin: const Offset(0, 0.1), end: Offset.zero, duration: 300.ms),
      ] : [],
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) return 'today';
    if (difference.inDays == 1) return 'yesterday';
    if (difference.inDays < 7) return '${difference.inDays} days ago';
    if (difference.inDays < 30) return '${(difference.inDays / 7).floor()} weeks ago';
    return '${date.day}/${date.month}/${date.year}';
  }

  void _showAchievementDetail(AchievementModel achievement) {
    showDialog(
      context: context,
      builder: (context) => AchievementUnlockPopup(
        achievement: achievement,
      ),
    );
  }

  void _showAchievementProgress(
    AchievementModel achievement,
    StudentModel student,
    bool isEarned,
  ) {
    if (isEarned) {
      _showAchievementDetail(achievement);
      return;
    }

    // Calculate progress
    int currentValue = 0;
    String unit = '';

    switch (achievement.requirementType) {
      case 'streak':
        currentValue = student.stats?.currentStreak ?? 0;
        unit = 'day${currentValue == 1 ? '' : 's'}';
        break;
      case 'books':
        currentValue = student.stats?.totalBooksRead ?? 0;
        unit = 'book${currentValue == 1 ? '' : 's'}';
        break;
      case 'minutes':
        currentValue = student.stats?.totalMinutesRead ?? 0;
        unit = 'minute${currentValue == 1 ? '' : 's'}';
        break;
      case 'days':
        currentValue = student.stats?.totalReadingDays ?? 0;
        unit = 'day${currentValue == 1 ? '' : 's'}';
        break;
    }

    final progress = (currentValue / achievement.requiredValue).clamp(0.0, 1.0);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: LumiBorders.shapeLarge,
        title: Row(
          children: [
            Text(achievement.icon),
            LumiGap.horizontalXS,
            Expanded(
              child: Text(
                achievement.name,
                style: LumiTextStyles.h3(),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              achievement.description,
              style: LumiTextStyles.body(),
            ),
            LumiGap.s,
            LinearProgressIndicator(
              value: progress,
              backgroundColor: AppColors.charcoal.withValues(alpha: 0.3),
              color: Color(achievement.rarity.color),
            ),
            LumiGap.xs,
            Text(
              '$currentValue / ${achievement.requiredValue} $unit',
              style: LumiTextStyles.bodyLarge(),
            ),
          ],
        ),
        actions: [
          LumiTextButton(
            onPressed: () => Navigator.pop(context),
            text: 'Close',
          ),
        ],
      ),
    );
  }
}
