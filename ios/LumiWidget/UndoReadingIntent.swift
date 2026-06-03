import AppIntents
import WidgetKit

/// Fired by the widget's "Undo" button during the post-tap undo window.
///
/// Pairs with `LogReadingIntent`: reverses the enqueue + optimistic flag +
/// undo-window timestamp written when the parent tapped "Log reading". Because
/// the Flutter app's `WidgetDataService.drainPendingWidgetLogs` skips entries
/// while their undo window is still open, no Firestore write has happened yet
/// — clearing the queue here means the log was never committed and there's
/// nothing to delete.
///
/// After the 10-second window closes (`undoUntil <= now`), the widget swaps
/// this CTA for the normal "View today" celebrating CTA and undo is handled
/// in-app via the post-commit banner instead.
@available(iOS 17.0, *)
struct UndoReadingIntent: AppIntent {
    static var title: LocalizedStringResource = "Undo Reading Log"
    static var description = IntentDescription(
        "Reverses a reading log that was just queued from the widget."
    )

    @Parameter(title: "Child")
    var studentId: String

    init() {}

    init(studentId: String) {
        self.studentId = studentId
    }

    func perform() async throws -> some IntentResult {
        WidgetLogQueue.cancel(studentId: studentId)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
