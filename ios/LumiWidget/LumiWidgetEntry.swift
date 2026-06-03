import WidgetKit
import Foundation

// MARK: - Display Mode

enum LumiDisplayMode {
    /// Not logged yet and it's before 7pm — show a gentle nudge.
    case reminder
    /// Reading logged for today — celebrate the streak.
    case celebrating
    /// Not logged yet and it's 7pm or later — streak urgency.
    case streakAtRisk
}

// MARK: - Timeline Entry

struct LumiWidgetEntry: TimelineEntry {
    let date: Date
    let studentId: String
    let firstName: String
    let characterId: String
    let currentStreak: Int
    let minutesReadToday: Int
    let targetMinutes: Int
    let loggedToday: Bool
    let displayMode: LumiDisplayMode
    /// True while the 10-second post-tap undo window is open for this child.
    /// In celebrating mode this swaps the "View today" CTA for an "Undo"
    /// button driven by `UndoReadingIntent`.
    let undoAvailable: Bool
    /// When the undo window expires, used by the provider to schedule the next
    /// timeline refresh exactly at the flip from "Undo" to "View today".
    let undoExpiresAt: Date?

    // Shown in the widget gallery before real data is available.
    static var placeholder: LumiWidgetEntry {
        LumiWidgetEntry(
            date: Date(),
            studentId: "",
            firstName: "Oliver",
            characterId: "character_default",
            currentStreak: 7,
            minutesReadToday: 0,
            targetMinutes: 20,
            loggedToday: false,
            displayMode: .reminder,
            undoAvailable: false,
            undoExpiresAt: nil
        )
    }
}
