import WidgetKit
import SwiftUI

// MARK: - Widget Definition

/// The Lumi home screen widget. iOS 17+ only.
///
/// Long-press → Edit Widget surfaces the "Choose child" picker defined in
/// `SelectChildIntent`, letting parents with multiple linked children pin a
/// widget instance to a specific child. The default sentinel
/// (`ChildEntity.activeChildSentinel`) keeps the historical behaviour of
/// following whichever child is currently active in the app.
struct LumiWidget: Widget {
    static let kind = "LumiWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: Self.kind,
            intent: SelectChildIntent.self,
            provider: LumiWidgetIntentProvider()
        ) { entry in
            LumiWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    LumiWidgetEntryView.backgroundFor(entry)
                }
        }
        .configurationDisplayName("Lumi Reading")
        .description("Track your child's daily reading and streak.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Bundle Entry Point

@main
struct LumiWidgetBundle: WidgetBundle {
    var body: some Widget {
        LumiWidget()
    }
}
