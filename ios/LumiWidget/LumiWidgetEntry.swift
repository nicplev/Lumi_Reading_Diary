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
            displayMode: .reminder
        )
    }
}
