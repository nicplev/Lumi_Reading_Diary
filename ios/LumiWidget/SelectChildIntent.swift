import AppIntents
import WidgetKit

/// Widget configuration intent fired when the parent long-presses the widget
/// → Edit Widget. Lets them pin the widget to a specific linked child, or
/// keep the default "follow the active child in the app" behaviour.
struct SelectChildIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose child"
    static var description = IntentDescription(
        "Pick which child this widget should show. Defaults to whichever child is active in the Lumi app."
    )

    @Parameter(title: "Child")
    var child: ChildEntity?

    init() {}

    init(child: ChildEntity?) {
        self.child = child
    }
}
