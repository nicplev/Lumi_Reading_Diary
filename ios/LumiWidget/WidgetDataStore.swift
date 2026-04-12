import Foundation

// MARK: - Codable payload structs (mirror the JSON written by WidgetDataService.dart)

struct WidgetPayload: Codable {
    let schemaVersion: Int
    let updatedAt: String
    let selectedChildId: String
    let children: [ChildPayload]
}

struct ChildPayload: Codable {
    let studentId: String
    let firstName: String
    let characterId: String
    let currentStreak: Int
    let lastReadingDate: String
    let minutesReadToday: Int
    let targetMinutes: Int
    let loggedToday: Bool
}

// MARK: - Data store

struct WidgetDataStore {
    static let appGroupId = "group.com.lumi.lumiReadingTracker"
    static let dataKey = "lumi_widget_data"

    /// Reads the JSON payload and builds a timeline entry for the given child.
    /// Falls back to the placeholder entry if data is missing or malformed.
    static func buildEntry(forChildId childId: String) -> LumiWidgetEntry {
        guard
            let defaults = UserDefaults(suiteName: appGroupId),
            let jsonString = defaults.string(forKey: dataKey),
            let data = jsonString.data(using: .utf8),
            let payload = try? JSONDecoder().decode(WidgetPayload.self, from: data)
        else {
            return .placeholder
        }

        let targetId = childId.isEmpty ? payload.selectedChildId : childId
        guard let child = payload.children.first(where: { $0.studentId == targetId })
                          ?? payload.children.first
        else {
            return .placeholder
        }

        return LumiWidgetEntry(
            date: Date(),
            studentId: child.studentId,
            firstName: child.firstName,
            characterId: child.characterId,
            currentStreak: child.currentStreak,
            minutesReadToday: child.minutesReadToday,
            targetMinutes: max(child.targetMinutes, 1),
            loggedToday: child.loggedToday,
            displayMode: displayMode(for: child)
        )
    }

    /// Returns all children from the stored payload (used by the intent handler
    /// to populate the child-picker in the widget configuration UI).
    static func allChildren() -> [(id: String, name: String)] {
        guard
            let defaults = UserDefaults(suiteName: appGroupId),
            let jsonString = defaults.string(forKey: dataKey),
            let data = jsonString.data(using: .utf8),
            let payload = try? JSONDecoder().decode(WidgetPayload.self, from: data)
        else {
            return []
        }
        return payload.children.map { ($0.studentId, $0.firstName) }
    }

    // MARK: Private

    private static func displayMode(for child: ChildPayload) -> LumiDisplayMode {
        if child.loggedToday { return .celebrating }
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 19 ? .streakAtRisk : .reminder
    }
}
