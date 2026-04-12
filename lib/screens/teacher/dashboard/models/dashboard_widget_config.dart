/// Stores which dashboard widgets a teacher has enabled and their display order.
///
/// Persisted inside the teacher's `UserModel.preferences` map under the
/// key `dashboardWidgets`.
class DashboardWidgetConfig {
  final List<String> activeWidgetIds;
  final int version;

  static const int currentVersion = 1;
  static const List<String> defaultWidgetIds = [
    'engagement',
    'recent_reading',
    'weekly_chart',
    'priority_nudges',
  ];

  const DashboardWidgetConfig({
    required this.activeWidgetIds,
    this.version = currentVersion,
  });

  factory DashboardWidgetConfig.fromPreferences(Map<String, dynamic>? prefs) {
    if (prefs == null || prefs['dashboardWidgets'] == null) {
      return DashboardWidgetConfig(
          activeWidgetIds: List<String>.from(defaultWidgetIds));
    }
    return DashboardWidgetConfig(
      activeWidgetIds: List<String>.from(prefs['dashboardWidgets']),
      version: prefs['dashboardVersion'] ?? currentVersion,
    );
  }

  Map<String, dynamic> toPreferencesMap() => {
        'dashboardWidgets': activeWidgetIds,
        'dashboardVersion': version,
      };

  bool hasWidget(String id) => activeWidgetIds.contains(id);

  DashboardWidgetConfig addWidget(String id) {
    if (activeWidgetIds.contains(id)) return this;
    return DashboardWidgetConfig(
      activeWidgetIds: [...activeWidgetIds, id],
      version: version,
    );
  }

  DashboardWidgetConfig removeWidget(String id) {
    return DashboardWidgetConfig(
      activeWidgetIds: activeWidgetIds.where((w) => w != id).toList(),
      version: version,
    );
  }

  DashboardWidgetConfig reorder(int oldIndex, int newIndex) {
    final list = List<String>.from(activeWidgetIds);
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    return DashboardWidgetConfig(activeWidgetIds: list, version: version);
  }
}
