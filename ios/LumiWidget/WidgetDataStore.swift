import Foundation

// MARK: - Codable payload structs (mirror the JSON written by WidgetDataService.dart)

struct WidgetPayload: Codable {
    let schemaVersion: Int
    let accountRole: String?
    let updatedAt: String
    let selectedChildId: String
    let children: [ChildPayload]
    let teacherDashboard: TeacherDashboardPayload?
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

struct TeacherDashboardPayload: Codable {
    let teacherId: String
    let schoolId: String
    let classId: String
    let className: String
    let totalStudents: Int
    let readTodayCount: Int
    let sessionsTodayCount: Int
    let teacherLoggedTodayCount: Int
    let onStreakCount: Int
    let totalMinutesToday: Int
    let todayDate: String
    let calendarDays: [TeacherCalendarDayPayload]
    let topReaders: [TeacherTopReaderPayload]

    static var placeholder: TeacherDashboardPayload {
        TeacherDashboardPayload(
            teacherId: "teacher",
            schoolId: "school",
            classId: "class",
            className: "Class",
            totalStudents: 24,
            readTodayCount: 14,
            sessionsTodayCount: 18,
            teacherLoggedTodayCount: 3,
            onStreakCount: 9,
            totalMinutesToday: 360,
            todayDate: "2026-07-08",
            calendarDays: (0..<42).map { index in
                let sample = [0, 1, 3, 7, 14, 20]
                return TeacherCalendarDayPayload(
                    date: "2026-07-\(String(format: "%02d", (index % 28) + 1))",
                    readCount: sample[index % sample.count]
                )
            },
            topReaders: [
                TeacherTopReaderPayload(studentId: "s1", firstName: "Sophie", characterId: "green_lumi", minutes: 120),
                TeacherTopReaderPayload(studentId: "s2", firstName: "Harry", characterId: "lumi_pig", minutes: 85),
                TeacherTopReaderPayload(studentId: "s3", firstName: "Lincon", characterId: "blue_lumi", minutes: 60)
            ]
        )
    }
}

struct TeacherCalendarDayPayload: Codable {
    let date: String
    let readCount: Int
}

struct TeacherTopReaderPayload: Codable {
    let studentId: String
    let firstName: String
    let characterId: String
    let minutes: Int
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

        // Two sentinels both mean "fall back to App Group selectedChildId":
        //   • empty string (provider passes this when configuration.child is nil)
        //   • ChildEntity.activeChildId (persisted form of the picker's
        //     "Active child in app" sentinel entity)
        let isActiveSentinel = childId.isEmpty || childId == ChildEntity.activeChildId
        let targetId = isActiveSentinel ? payload.selectedChildId : childId
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

    /// Reads the teacher dashboard payload. It only returns teacher data when
    /// the App Group payload explicitly identifies the active account as a
    /// teacher; parent/signed-out payloads render the teacher widget's empty
    /// state instead of leaking stale student names.
    static func buildTeacherEntry(kind: LumiTeacherWidgetKind) -> LumiTeacherWidgetEntry {
        guard
            let defaults = UserDefaults(suiteName: appGroupId),
            let jsonString = defaults.string(forKey: dataKey),
            let data = jsonString.data(using: .utf8),
            let payload = try? JSONDecoder().decode(WidgetPayload.self, from: data),
            payload.accountRole == "teacher",
            let dashboard = payload.teacherDashboard
        else {
            return .signedOut(kind: kind)
        }

        return LumiTeacherWidgetEntry(
            date: Date(),
            kind: kind,
            dashboard: dashboard
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
        guard payload.accountRole != "teacher" else { return [] }
        return payload.children.map { ($0.studentId, $0.firstName) }
    }

    // MARK: Private

    private static func displayMode(for child: ChildPayload) -> LumiDisplayMode {
        if child.loggedToday { return .celebrating }
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 19 ? .streakAtRisk : .reminder
    }
}
