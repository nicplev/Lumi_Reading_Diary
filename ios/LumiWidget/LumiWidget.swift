import WidgetKit
import SwiftUI

// MARK: - Widget Definition

struct LumiWidget: Widget {
    static let kind = "LumiWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: LumiWidgetProvider()) { entry in
            if #available(iOS 17.0, *) {
                LumiWidgetEntryView(entry: entry)
                    .containerBackground(for: .widget) {
                        LumiWidgetEntryView.backgroundFor(entry)
                    }
            } else {
                ZStack {
                    LumiWidgetEntryView.backgroundFor(entry)
                    LumiWidgetEntryView(entry: entry)
                }
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
