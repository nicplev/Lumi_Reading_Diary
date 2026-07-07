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
        .description("Parent and guardian widget for logging a child's daily reading.")
        .supportedFamilies([.systemSmall])
    }
}

struct LumiTeacherTodayWidget: Widget {
    static let kind = "LumiTeacherTodayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: Self.kind,
            provider: LumiTeacherWidgetProvider(kind: .today)
        ) { entry in
            LumiTeacherWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    Color.lumiCream
                }
        }
        .configurationDisplayName("Lumi Class Today")
        .description("Teacher-only widget showing today's class reading percentage.")
        .supportedFamilies([.systemSmall])
    }
}

struct LumiTeacherTopReadersWidget: Widget {
    static let kind = "LumiTeacherTopReadersWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: Self.kind,
            provider: LumiTeacherWidgetProvider(kind: .topReaders)
        ) { entry in
            LumiTeacherWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    Color.lumiCream
                }
        }
        .configurationDisplayName("Lumi Top Readers")
        .description("Teacher-only widget showing top readers in your selected class.")
        .supportedFamilies([.systemSmall])
    }
}

struct LumiTeacherCalendarWidget: Widget {
    static let kind = "LumiTeacherCalendarWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: Self.kind,
            provider: LumiTeacherWidgetProvider(kind: .readingCalendar)
        ) { entry in
            LumiTeacherWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    Color.lumiCream
                }
        }
        .configurationDisplayName("Lumi Reading Calendar")
        .description("Teacher-only widget showing a six-week class reading heatmap.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Bundle Entry Point

@main
struct LumiWidgetBundle: WidgetBundle {
    var body: some Widget {
        LumiWidget()
        LumiTeacherTodayWidget()
        LumiTeacherTopReadersWidget()
        LumiTeacherCalendarWidget()
    }
}
