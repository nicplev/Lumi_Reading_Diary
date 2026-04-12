import 'package:flutter/material.dart';

import '../widgets/dashboard_achievement_spotlight_card.dart';
import '../widgets/dashboard_engagement_card.dart';
import '../widgets/dashboard_group_comparison_card.dart';
import '../widgets/dashboard_reading_sentiment_card.dart';
import '../widgets/dashboard_recent_reading_card.dart';
import '../widgets/dashboard_top_readers_card.dart';
import '../widgets/dashboard_weekly_chart.dart';
import '../widgets/dashboard_priority_nudges.dart';
import 'dashboard_widget_context.dart';

/// Shared data that a widget may require from the dashboard.
///
/// If a widget declares a dependency, the dashboard will ensure that data is
/// fetched before building the widget.  Widgets whose dependency set is empty
/// never block on any shared fetch.
enum WidgetDataDependency { students, weeklyLogs, readingGroups }

/// Metadata + builder for a single dashboard widget.
class DashboardWidgetDefinition {
  final String id;
  final String displayName;
  final String description;
  final IconData icon;
  final Set<WidgetDataDependency> dataDependencies;
  final Widget Function(DashboardWidgetContext ctx) builder;

  const DashboardWidgetDefinition({
    required this.id,
    required this.displayName,
    required this.description,
    required this.icon,
    required this.dataDependencies,
    required this.builder,
  });
}

/// Central catalogue of every widget that can appear on the teacher dashboard.
///
/// To add a new widget in the future, register it here and it will
/// automatically appear in the widget gallery.
class DashboardWidgetRegistry {
  DashboardWidgetRegistry._();

  static final Map<String, DashboardWidgetDefinition> _widgets = {
    'engagement': DashboardWidgetDefinition(
      id: 'engagement',
      displayName: "Today's Engagement",
      description: 'Reading engagement ring and daily stats',
      icon: Icons.donut_large_rounded,
      dataDependencies: {WidgetDataDependency.students},
      builder: (ctx) => DashboardEngagementCard(
        classModel: ctx.classModel,
        schoolId: ctx.schoolId,
        students: ctx.students,
        resetSignal: ctx.engagementResetSignal,
      ),
    ),
    'recent_reading': DashboardWidgetDefinition(
      id: 'recent_reading',
      displayName: 'Recent Reading',
      description: 'Last 5 reading logs from your class',
      icon: Icons.auto_stories_rounded,
      dataDependencies: {WidgetDataDependency.students},
      builder: (ctx) => DashboardRecentReadingCard(
        classModel: ctx.classModel,
        schoolId: ctx.schoolId,
        students: ctx.students,
        onViewAll: ctx.onViewAllReading,
      ),
    ),
    'weekly_chart': DashboardWidgetDefinition(
      id: 'weekly_chart',
      displayName: 'Weekly Chart',
      description: "Bar chart of this week's reading activity",
      icon: Icons.bar_chart_rounded,
      dataDependencies: {},
      builder: (ctx) => DashboardWeeklyChart(
        classModel: ctx.classModel,
        schoolId: ctx.schoolId,
      ),
    ),
    'priority_nudges': DashboardWidgetDefinition(
      id: 'priority_nudges',
      displayName: 'Priority Nudges',
      description: 'Actionable alerts for inactivity and milestones',
      icon: Icons.notifications_active_rounded,
      dataDependencies: {WidgetDataDependency.students},
      builder: (ctx) => DashboardPriorityNudges(
        classModel: ctx.classModel,
        teacher: ctx.teacher,
        students: ctx.students,
        onSeeAll: ctx.onViewAllReading,
      ),
    ),
    'top_readers': DashboardWidgetDefinition(
      id: 'top_readers',
      displayName: 'Top Readers',
      description: 'Leaderboard of top readers this week',
      icon: Icons.emoji_events_rounded,
      dataDependencies: {
        WidgetDataDependency.students,
        WidgetDataDependency.weeklyLogs,
      },
      builder: (ctx) => DashboardTopReadersCard(
        weeklyLogs: ctx.weeklyLogs,
        students: ctx.students,
      ),
    ),
    'reading_sentiment': DashboardWidgetDefinition(
      id: 'reading_sentiment',
      displayName: 'Reading Sentiment',
      description: "How your class felt about reading this week",
      icon: Icons.sentiment_satisfied_alt_rounded,
      dataDependencies: {WidgetDataDependency.weeklyLogs},
      builder: (ctx) => DashboardReadingSentimentCard(
        weeklyLogs: ctx.weeklyLogs,
      ),
    ),
    'achievement_spotlight': DashboardWidgetDefinition(
      id: 'achievement_spotlight',
      displayName: 'Achievement Spotlight',
      description: 'Recent achievements earned by your class',
      icon: Icons.military_tech_rounded,
      dataDependencies: {WidgetDataDependency.students},
      builder: (ctx) => DashboardAchievementSpotlightCard(
        recentAchievements: ctx.recentAchievements,
      ),
    ),
    'group_comparison': DashboardWidgetDefinition(
      id: 'group_comparison',
      displayName: 'Group Comparison',
      description: "Compare reading groups' engagement this week",
      icon: Icons.groups_rounded,
      dataDependencies: {
        WidgetDataDependency.weeklyLogs,
        WidgetDataDependency.readingGroups,
      },
      builder: (ctx) => DashboardGroupComparisonCard(
        weeklyLogs: ctx.weeklyLogs,
        readingGroups: ctx.readingGroups,
      ),
    ),
  };

  static List<DashboardWidgetDefinition> get allWidgets =>
      _widgets.values.toList();

  static DashboardWidgetDefinition? get(String id) => _widgets[id];

  /// Returns widgets that are **not** currently active.
  static List<DashboardWidgetDefinition> getInactive(
          List<String> activeIds) =>
      _widgets.values.where((w) => !activeIds.contains(w.id)).toList();
}
