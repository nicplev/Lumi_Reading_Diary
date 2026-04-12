import WidgetKit

// MARK: - Timeline Provider

/// Provides timeline entries to WidgetKit.
/// Uses `TimelineProvider` (not IntentTimelineProvider) for the base implementation.
/// The child selection is handled by `SelectChildIntent` (intent definition file)
/// wired in `LumiWidget.swift`.
struct LumiWidgetProvider: TimelineProvider {

    func placeholder(in context: Context) -> LumiWidgetEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (LumiWidgetEntry) -> Void) {
        completion(WidgetDataStore.buildEntry(forChildId: ""))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LumiWidgetEntry>) -> Void) {
        let entry = WidgetDataStore.buildEntry(forChildId: "")

        // Schedule the next refresh:
        //  • If not yet 7pm and the child hasn't read → refresh at 7pm to switch to "streakAtRisk".
        //  • Otherwise → refresh at midnight so the widget resets for the new day.
        let calendar = Calendar.current
        let now = Date()

        let sevenPM = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: now) ?? now
        let midnight = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now) ?? now)

        let nextRefresh: Date
        if now < sevenPM && !entry.loggedToday {
            nextRefresh = sevenPM
        } else {
            nextRefresh = midnight
        }

        let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
        completion(timeline)
    }
}
