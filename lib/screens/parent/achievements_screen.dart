import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lumi_reading_tracker/data/models/achievement_model.dart';
import 'package:lumi_reading_tracker/data/models/student_model.dart';
import 'package:lumi_reading_tracker/core/widgets/glass/glass_achievement_card.dart';
import 'package:lumi_reading_tracker/core/theme/app_colors.dart';
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
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primaryBlue.withOpacity(0.1),
              AppColors.secondaryOrange.withOpacity(0.1),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
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
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          const Text(
            '🏆 Achievements',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilter() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _buildCategoryChip(
            'All',
            null,
            _selectedCategory == null,
          ),
          const SizedBox(width: 8),
          ...AchievementCategory.values.map((category) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
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
      backgroundColor: Colors.white.withOpacity(0.1),
      selectedColor: AppColors.primaryBlue.withOpacity(0.3),
      checkmarkColor: Colors.white,
      labelStyle: TextStyle(
        color: Colors.white,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      ),
      side: BorderSide(
        color: selected
            ? AppColors.primaryBlue.withOpacity(0.5)
            : Colors.white.withOpacity(0.3),
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: AppColors.primaryBlue.withOpacity(0.3),
          borderRadius: BorderRadius.circular(16),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white.withOpacity(0.6),
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
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: filteredAchievements.length,
          itemBuilder: (context, index) {
            return GlassAchievementCard(
              achievement: filteredAchievements[index],
              animate: index < 5, // Animate first 5
              onTap: () => _showAchievementDetail(filteredAchievements[index]),
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
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
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
            color: AppColors.primaryBlue,
          ),
          const SizedBox(height: 16),
          Text(
            'Loading achievements...',
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 16,
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
            color: Colors.red,
          ),
          const SizedBox(height: 16),
          Text(
            'Error loading achievements',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            error,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 14,
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
            style: const TextStyle(fontSize: 64),
          )
              .animate(onPlay: (controller) => controller.repeat())
              .shimmer(duration: 2000.ms)
              .shake(hz: 2, rotation: 0.05),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
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
        title: Row(
          children: [
            Text(achievement.icon),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                achievement.name,
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(achievement.description),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey.withOpacity(0.3),
              color: Color(achievement.rarity.color),
            ),
            const SizedBox(height: 8),
            Text(
              '$currentValue / ${achievement.requiredValue} $unit',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
