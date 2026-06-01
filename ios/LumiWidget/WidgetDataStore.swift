import Foundation
import os

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
            widgetDebugLog.notice("buildEntry — no/invalid payload, returning placeholder. requested childId=\(childId, privacy: .public)")
            return .placeholder
        }

        // Two sentinels both mean "fall back to App Group selectedChildId":
        //   • empty string (legacy / explicit "use default")
        //   • ChildEntity.activeChildId (persisted form of the picker's
        //     "Active child in app" sentinel entity)
        let isActiveSentinel = childId.isEmpty || childId == ChildEntity.activeChildId
        let targetId = isActiveSentinel ? payload.selectedChildId : childId
        let exactMatch = payload.children.first(where: { $0.studentId == targetId })
        let availableIds = payload.children.map { $0.studentId }.joined(separator: ",")
        widgetDebugLog.notice("buildEntry — requested='\(childId, privacy: .public)' resolved targetId='\(targetId, privacy: .public)' exactMatch=\(exactMatch != nil, privacy: .public) availableIds=[\(availableIds, privacy: .public)] selectedChildId='\(payload.selectedChildId, privacy: .public)'")
        guard let child = exactMatch ?? payload.children.first
        else {
            return .placeholder
        }
        widgetDebugLog.notice("buildEntry — rendering child id=\(child.studentId, privacy: .public) name=\(child.firstName, privacy: .public)")

        // Rec 4: reflect an optimistic widget-intent tap before the Flutter
        // app has reconciled the real Firestore write.
        let optimisticallyLogged =
            WidgetLogQueue.isOptimisticallyLogged(studentId: child.studentId)
        let effectiveLogged = child.loggedToday || optimisticallyLogged

        return LumiWidgetEntry(
            date: Date(),
            studentId: child.studentId,
            firstName: child.firstName,
            characterId: child.characterId,
            currentStreak: child.currentStreak,
            minutesReadToday: child.minutesReadToday,
            targetMinutes: max(child.targetMinutes, 1),
            loggedToday: effectiveLogged,
            displayMode: effectiveLogged ? .celebrating : displayMode(for: child)
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
