import WidgetKit
import SwiftUI

// MARK: - Widget Definition

struct LumiWidget: Widget {
    static let kind = "LumiWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: LumiWidgetProvider()) { entry in
            if #available(iOS 17.0, *) {
                LumiWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                LumiWidgetEntryView(entry: entry)
                    .padding()
                    .background()
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
