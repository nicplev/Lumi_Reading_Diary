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
    /// `studentId -> ISO8601` map of "undo window expires at" timestamps. While
    /// `Date() < undoUntil[studentId]`, the widget renders a "Logged! Undo"
    /// state and `WidgetDataService.drainPendingWidgetLogs` (Dart side) skips
    /// the entry so no Firestore write happens until the window closes.
    static let undoUntilKey = "lumi_widget_undo_until"
    /// How long the post-tap undo window lasts on the widget.
    static let undoWindowSeconds: TimeInterval = 10

    /// Appends a tap to the pending queue, deduped per child per calendar day,
    /// records an optimistic "logged today" flag, and opens the 10-second
    /// undo window for this child.
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

        var undoUntil = defaults.dictionary(forKey: undoUntilKey) as? [String: String] ?? [:]
        undoUntil[studentId] = isoFormatter.string(from: Date().addingTimeInterval(undoWindowSeconds))
        defaults.set(undoUntil, forKey: undoUntilKey)
    }

    /// Reverses a recent `enqueue` for the given child: drops the pending
    /// queue entry, clears the optimistic flag, and closes the undo window.
    /// Safe to call when nothing is enqueued — fields just no-op.
    static func cancel(studentId: String) {
        guard !studentId.isEmpty,
              let defaults = UserDefaults(suiteName: appGroupId) else { return }

        let today = dateKey(Date())

        var pending = decodePending(defaults.string(forKey: pendingKey))
        pending.removeAll { $0.studentId == studentId && $0.date == today }
        defaults.set(encodePending(pending), forKey: pendingKey)

        if var optimistic = defaults.dictionary(forKey: optimisticKey) as? [String: String] {
            optimistic.removeValue(forKey: studentId)
            defaults.set(optimistic, forKey: optimisticKey)
        }

        if var undoUntil = defaults.dictionary(forKey: undoUntilKey) as? [String: String] {
            undoUntil.removeValue(forKey: studentId)
            defaults.set(undoUntil, forKey: undoUntilKey)
        }
    }

    /// True when the child has been optimistically logged for today.
    static func isOptimisticallyLogged(studentId: String) -> Bool {
        guard let defaults = UserDefaults(suiteName: appGroupId) else { return false }
        let optimistic =
            defaults.dictionary(forKey: optimisticKey) as? [String: String] ?? [:]
        return optimistic[studentId] == dateKey(Date())
    }

    /// The future date until which the post-tap undo window is open for the
    /// given child, or nil if no window is active. Drives both the widget UI
    /// ("Undo" CTA) and the timeline-refresh schedule (flip to normal
    /// celebrating state at expiry).
    static func undoUntil(studentId: String) -> Date? {
        guard let defaults = UserDefaults(suiteName: appGroupId),
              let dict = defaults.dictionary(forKey: undoUntilKey) as? [String: String],
              let iso = dict[studentId],
              let date = isoFormatter.date(from: iso),
              date > Date()
        else { return nil }
        return date
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

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
