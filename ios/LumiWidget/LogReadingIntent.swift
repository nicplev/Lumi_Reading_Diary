import AppIntents
import WidgetKit

/// App Intent fired by the widget's "Log reading" button on iOS 17+.
///
/// The widget extension has no Firebase SDK, so it cannot write to Firestore
/// directly. Instead the tap is queued into App Group storage; the Flutter app
/// drains the queue (see `WidgetDataService.drainPendingWidgetLogs`) on its
/// next launch or foreground and performs the real write. This is an
/// optimistic queue-and-reconcile model — see docs/parent-ux-research.md.
@available(iOS 17.0, *)
struct LogReadingIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Reading"
    static var description = IntentDescription("Logs today's reading for a child.")

    /// The student whose reading is being logged. Carried from the widget
    /// entry so the Flutter app knows which child to record against.
    @Parameter(title: "Child")
    var studentId: String

    init() {}

    init(studentId: String) {
        self.studentId = studentId
    }

    func perform() async throws -> some IntentResult {
        WidgetLogQueue.enqueue(studentId: studentId)
        // Re-render the timeline so the widget flips to its optimistic
        // "logged" state immediately.
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// A single queued widget log tap.
struct PendingWidgetLog: Codable {
    let studentId: String
    let date: String // yyyy-MM-dd, for per-day dedupe
}

/// App Group-backed queue of widget log taps awaiting the Flutter app.
///
/// The pending queue is stored as a JSON string so the `home_widget` plugin
/// (which only round-trips String/num/bool) can read it from Dart.
enum WidgetLogQueue {
    static let appGroupId = "group.com.lumi.lumiReadingTracker"
    /// JSON-encoded `[PendingWidgetLog]` awaiting reconciliation by the app.
    static let pendingKey = "lumi_pending_widget_logs"
    /// `studentId -> yyyy-MM-dd` map of optimistically-logged children, so the
    /// widget can show "logged" before the Flutter app performs the write.
    static let optimisticKey = "lumi_optimistic_logged_ids"

    /// Appends a tap to the pending queue, deduped per child per calendar day,
    /// and records an optimistic "logged today" flag for the child.
    static func enqueue(studentId: String) {
        guard !studentId.isEmpty,
              let defaults = UserDefaults(suiteName: appGroupId) else { return }

        let today = dateKey(Date())

        var pending = decodePending(defaults.string(forKey: pendingKey))
        let alreadyQueued = pending.contains {
            $0.studentId == studentId && $0.date == today
        }
        if !alreadyQueued {
            pending.append(PendingWidgetLog(studentId: studentId, date: today))
            defaults.set(encodePending(pending), forKey: pendingKey)
        }

        var optimistic =
            defaults.dictionary(forKey: optimisticKey) as? [String: String] ?? [:]
        optimistic[studentId] = today
        defaults.set(optimistic, forKey: optimisticKey)
    }

    /// True when the child has been optimistically logged for today.
    static func isOptimisticallyLogged(studentId: String) -> Bool {
        guard let defaults = UserDefaults(suiteName: appGroupId) else { return false }
        let optimistic =
            defaults.dictionary(forKey: optimisticKey) as? [String: String] ?? [:]
        return optimistic[studentId] == dateKey(Date())
    }

    // MARK: Private

    private static func decodePending(_ json: String?) -> [PendingWidgetLog] {
        guard let json, let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([PendingWidgetLog].self, from: data)
        else { return [] }
        return decoded
    }

    private static func encodePending(_ logs: [PendingWidgetLog]) -> String {
        guard let data = try? JSONEncoder().encode(logs),
              let json = String(data: data, encoding: .utf8)
        else { return "[]" }
        return json
    }

    private static func dateKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}
