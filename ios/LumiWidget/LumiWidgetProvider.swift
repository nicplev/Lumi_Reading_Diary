import WidgetKit
import AppIntents

/// Drives the configurable Lumi widget. Reads the configured child from
/// `SelectChildIntent.child` and renders it. When the parent chose the
/// "Active child in app" sentinel (or hasn't customised the widget),
/// `child?.id` resolves to the empty string and
/// `WidgetDataStore.buildEntry(forChildId:)` falls back to the App Group
/// `selectedChildId`, preserving today's default behaviour.
struct LumiWidgetIntentProvider: AppIntentTimelineProvider {
    typealias Intent = SelectChildIntent
    typealias Entry = LumiWidgetEntry

    func placeholder(in context: Context) -> LumiWidgetEntry {
        .placeholder
    }

    func snapshot(for configuration: SelectChildIntent, in context: Context) async -> LumiWidgetEntry {
        WidgetDataStore.buildEntry(forChildId: configuration.child?.id ?? "")
    }

    func timeline(for configuration: SelectChildIntent, in context: Context) async -> Timeline<LumiWidgetEntry> {
        let entry = WidgetDataStore.buildEntry(forChildId: configuration.child?.id ?? "")
        return Timeline(entries: [entry], policy: .after(nextRefreshDate(for: entry)))
    }
}

// MARK: - Refresh schedule

/// Computes the next timeline refresh point:
///  • While the post-tap undo window is open → refresh exactly when it closes
///    so the "Undo" CTA flips back to "View today" without the parent needing
///    to touch the widget.
///  • If not yet 7pm and the child hasn't read → refresh at 7pm to switch to "streakAtRisk".
///  • Otherwise → refresh at midnight so the widget resets for the new day.
private func nextRefreshDate(for entry: LumiWidgetEntry) -> Date {
    let calendar = Calendar.current
    let now = Date()
    if let undoExpiresAt = entry.undoExpiresAt, undoExpiresAt > now {
        return undoExpiresAt
    }
    let sevenPM = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: now) ?? now
    let midnight = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now) ?? now)
    if now < sevenPM && !entry.loggedToday {
        return sevenPM
    }
    return midnight
}
