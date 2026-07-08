import Foundation
import SwiftUI
import WidgetKit

// MARK: - Lumi Design Tokens

extension Color {
    // Mirrors lib/theme/lumi_tokens.dart.
    static let lumiRed        = Color(red: 0.925, green: 0.271, blue: 0.267) // #EC4544
    static let lumiYellow     = Color(red: 0.949, green: 0.718, blue: 0.020) // #F2B705
    static let lumiGreen      = Color(red: 0.318, green: 0.729, blue: 0.396) // #51BA65
    static let lumiBlue       = Color(red: 0.337, green: 0.784, blue: 0.902) // #56C8E6
    static let lumiOrange     = Color(red: 0.980, green: 0.647, blue: 0.102) // #FAA51A

    static let lumiTintRed    = Color(red: 0.957, green: 0.710, blue: 0.718) // #F4B5B7
    static let lumiTintYellow = Color(red: 0.984, green: 0.910, blue: 0.624) // #FBE89F
    static let lumiTintGreen  = Color(red: 0.710, green: 0.855, blue: 0.722) // #B5DAB8
    static let lumiTintBlue   = Color(red: 0.784, green: 0.910, blue: 0.945) // #C8E8F1
    static let lumiTintOrange = Color(red: 0.996, green: 0.847, blue: 0.659) // #FED8A8

    static let lumiCream      = Color(red: 0.984, green: 0.980, blue: 0.965) // #FBFAF6
    static let lumiPaper      = Color.white
    static let lumiInk        = Color(red: 0.102, green: 0.102, blue: 0.102) // #1A1A1A
    static let lumiMuted      = Color(red: 0.420, green: 0.420, blue: 0.420) // #6B6B6B
    static let lumiRule       = Color(red: 0.898, green: 0.886, blue: 0.863) // #E5E2DC
}

enum LumiWidgetCharacterAssets {
    static func resolve(_ raw: String) -> String {
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if id.isEmpty || id == "character_default" {
            return "lumi_red_default"
        }
        return supported.contains(id) ? id : "lumi_red_default"
    }

    private static let supported: Set<String> = [
        "blue_crown",
        "blue_lumi",
        "blue_pig",
        "blue_space",
        "blue_tiger",
        "green_bear",
        "green_dj",
        "green_lumi",
        "light_blue_lumi",
        "lumi_bear",
        "lumi_cat",
        "lumi_chef",
        "lumi_cool_kid",
        "lumi_crown",
        "lumi_frog",
        "lumi_headphones",
        "lumi_ninja",
        "lumi_penguin",
        "lumi_pig",
        "lumi_pirate",
        "lumi_red_default",
        "lumi_shark",
        "lumi_space",
        "lumi_tiger",
        "lumi_wizard",
        "orange_lumi",
        "orange_penguin",
        "orange_wizard",
        "pink_frog",
        "pink_lumi",
        "pink_pirate",
        "pink_shark",
        "purple_cool_kid",
        "purple_lumi",
        "yellow_cat",
        "yellow_chef",
        "yellow_lumi",
        "yellow_ninja"
    ]
}

// MARK: - Main View

struct LumiWidgetEntryView: View {
    var entry: LumiWidgetEntry

    var body: some View {
        contentView
            .widgetURL(tapURL)
    }

    // MARK: Background

    @ViewBuilder
    static func backgroundFor(_: LumiWidgetEntry) -> some View {
        Color.lumiCream
    }

    // MARK: Layout

    private var contentView: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            centerRow
            Spacer(minLength: 0)
            ctaLabelView
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }

    private var headerRow: some View {
        Text(entry.firstName)
            .font(.system(size: 20, weight: .heavy, design: .rounded))
            .foregroundColor(.lumiInk)
            .lineLimit(1)
            .minimumScaleFactor(0.58)
    }

    private var centerRow: some View {
        HStack(alignment: .center, spacing: 4) {
            mascotView
            Spacer(minLength: 0)
            metricPanel
                .frame(width: 48, alignment: .trailing)
        }
    }

    private var mascotView: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(characterAssetName)
                .resizable()
                .scaledToFit()
                .frame(width: 82, height: 88)
                .shadow(color: Color.lumiInk.opacity(0.10), radius: 5, x: 0, y: 3)

            Image(systemName: mascotBadgeIcon)
                .font(.system(size: 12, weight: .heavy))
                .foregroundColor(mascotBadgeForeground)
                .frame(width: 24, height: 24)
                .background(Circle().fill(mascotBadgeFill))
                .overlay(Circle().stroke(Color.lumiPaper, lineWidth: 2))
                .offset(x: 3, y: 0)
        }
        .frame(width: 88, height: 90, alignment: .bottomLeading)
    }

    @ViewBuilder
    private var metricPanel: some View {
        VStack(alignment: .trailing, spacing: 4) {
            switch entry.displayMode {
            case .reminder:
                EmptyView()
            case .celebrating:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundColor(.lumiGreen)
                if entry.currentStreak > 0 {
                    streakText
                }
            case .streakAtRisk:
                if entry.currentStreak > 0 {
                    streakText
                }
            }
        }
    }

    private var streakText: some View {
        HStack(spacing: 2) {
            Image(systemName: "flame.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.lumiOrange)
            Text("\(entry.currentStreak)d")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundColor(.lumiInk)
        }
    }

    // MARK: CTA Label

    // The CTA is intentionally not an iOS 17 AppIntent button. Every tap on the
    // widget goes through `widgetURL`: unlogged states open the app's normal
    // logging flow, while logged states open parent home.
    private var ctaLabelView: some View {
        HStack(spacing: 5) {
            Image(systemName: ctaIcon)
                .font(.system(size: 10, weight: .heavy))
            Text(ctaLabel)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .foregroundColor(.lumiPaper)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(Capsule().fill(ctaFill))
        .shadow(color: ctaFill.opacity(0.24), radius: 5, x: 0, y: 3)
    }

    // MARK: State Styling

    private var mascotBadgeIcon: String {
        switch entry.displayMode {
        case .reminder:     return "book.closed.fill"
        case .celebrating:  return "checkmark"
        case .streakAtRisk: return "bolt.fill"
        }
    }

    private var mascotBadgeFill: Color {
        switch entry.displayMode {
        case .reminder:     return .lumiBlue
        case .celebrating:  return .lumiGreen
        case .streakAtRisk: return .lumiYellow
        }
    }

    private var mascotBadgeForeground: Color {
        switch entry.displayMode {
        case .streakAtRisk: return .lumiInk
        default:            return .lumiPaper
        }
    }

    private var ctaLabel: String {
        switch entry.displayMode {
        case .reminder:     return "Log now"
        case .celebrating:  return "View today"
        case .streakAtRisk: return "Log now"
        }
    }

    private var ctaIcon: String {
        switch entry.displayMode {
        case .reminder:     return "plus"
        case .celebrating:  return "arrow.right"
        case .streakAtRisk: return "bolt.fill"
        }
    }

    private var ctaFill: Color {
        switch entry.displayMode {
        case .celebrating: return .lumiGreen
        default:           return .lumiRed
        }
    }

    // MARK: Character

    private var characterAssetName: String {
        LumiWidgetCharacterAssets.resolve(entry.characterId)
    }

    // MARK: Deep Link URL

    private var tapURL: URL {
        let action = entry.loggedToday ? "home" : "log"
        var components = URLComponents()
        components.scheme = "lumi"
        components.host = "widget"
        components.path = "/\(action)"
        components.queryItems = [
            URLQueryItem(name: "homeWidget", value: "1"),
            URLQueryItem(name: "childId", value: entry.studentId)
        ]
        return components.url ?? URL(string: "lumi://widget/home?homeWidget=1")!
    }
}

// MARK: - Teacher Widgets

struct LumiTeacherWidgetEntryView: View {
    let entry: LumiTeacherWidgetEntry

    var body: some View {
        Group {
            if let dashboard = entry.dashboard {
                teacherContent(dashboard)
            } else {
                signedOutContent
            }
        }
        .widgetURL(tapURL)
    }

    @ViewBuilder
    private func teacherContent(_ dashboard: TeacherDashboardPayload) -> some View {
        switch entry.kind {
        case .today:
            todayView(dashboard)
        case .topReaders:
            topReadersView(dashboard)
        case .readingCalendar:
            readingCalendarView(dashboard)
        }
    }

    private var signedOutContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundColor(.lumiInk)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                Image("lumi_red_default")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 58, height: 66)
                Spacer(minLength: 0)
                Text("Open\nLumi")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundColor(.lumiMuted)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(12)
        .background(Color.lumiCream)
    }

    private func todayView(_ dashboard: TeacherDashboardPayload) -> some View {
        let percent = dashboard.totalStudents > 0
            ? Int(round(Double(dashboard.readTodayCount) / Double(dashboard.totalStudents) * 100))
            : 0
        return VStack(alignment: .center, spacing: 7) {
            teacherHeader("Today", dashboard.className)
            Spacer(minLength: 0)
            HStack(alignment: .center, spacing: 7) {
                Image("light_blue_lumi")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 42, height: 48)
                    .shadow(color: Color.lumiInk.opacity(0.10), radius: 4, x: 0, y: 2)

                progressRing(percent: percent)
                    .frame(width: 66, height: 66)
            }
            Text("\(dashboard.readTodayCount)/\(dashboard.totalStudents) read today")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundColor(.lumiInk)
                .lineLimit(1)
                .minimumScaleFactor(0.64)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.lumiCream)
    }

    private func topReadersView(_ dashboard: TeacherDashboardPayload) -> some View {
        let readers = Array(dashboard.topReaders.prefix(3))
        let maxMinutes = max(readers.map(\.minutes).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 8) {
            teacherHeader("Top Readers", "")
            if readers.isEmpty {
                Spacer(minLength: 0)
                Text("No logs yet")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(.lumiMuted)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(readers.indices, id: \.self) { index in
                        topReaderRow(
                            rank: index + 1,
                            reader: readers[index],
                            maxMinutes: maxMinutes
                        )
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .background(Color.lumiCream)
    }

    private func readingCalendarView(_ dashboard: TeacherDashboardPayload) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            teacherHeader("Calendar", "6 weeks")
            calendarGrid(dashboard)
                .frame(maxWidth: .infinity, alignment: .center)
            Spacer(minLength: 0)
            calendarLegend
        }
        .padding(10)
        .background(Color.lumiCream)
    }

    private func teacherHeader(_ primary: String, _ secondary: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(primary)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundColor(.lumiInk)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
            Spacer(minLength: 2)
            if !secondary.isEmpty {
                Text(secondary)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(.lumiMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
            }
        }
    }

    private func progressRing(percent: Int) -> some View {
        let progress = min(max(Double(percent) / 100.0, 0), 1)
        return ZStack {
            Circle()
                .stroke(Color.lumiRule, lineWidth: 7)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Color.lumiBlue,
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text("\(percent)%")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundColor(.lumiInk)
                .minimumScaleFactor(0.62)
        }
    }

    private func topReaderRow(
        rank: Int,
        reader: TeacherTopReaderPayload,
        maxMinutes: Int
    ) -> some View {
        let fraction = CGFloat(reader.minutes) / CGFloat(maxMinutes)
        return HStack(spacing: 7) {
            Text("\(rank)")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundColor(rank == 1 ? .lumiYellow : .lumiMuted)
                .frame(width: 11)
            Image(LumiWidgetCharacterAssets.resolve(reader.characterId))
                .resizable()
                .scaledToFit()
                .frame(width: 25, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(reader.firstName)
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundColor(.lumiInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                    Spacer(minLength: 0)
                    Text("\(reader.minutes)m")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundColor(.lumiInk)
                        .lineLimit(1)
                }
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.lumiRule)
                    Capsule()
                        .fill(Color.lumiBlue)
                        .frame(width: max(CGFloat(8), CGFloat(82) * fraction))
                }
                .frame(height: 6)
            }
        }
    }

    private func calendarGrid(_ dashboard: TeacherDashboardPayload) -> some View {
        let days = Array(dashboard.calendarDays.suffix(42))
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(0..<6, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { column in
                        let index = row * 7 + column
                        RoundedRectangle(cornerRadius: 2)
                            .fill(calendarColor(
                                readCount: index < days.count ? days[index].readCount : 0,
                                totalStudents: dashboard.totalStudents
                            ))
                            .frame(width: 12, height: 12)
                    }
                }
            }
        }
    }

    private var calendarLegend: some View {
        HStack(spacing: 3) {
            Text("Less")
                .font(.system(size: 8, weight: .heavy, design: .rounded))
                .foregroundColor(.lumiMuted)
                .lineLimit(1)
                .frame(width: 24, alignment: .trailing)
            ForEach(legendColors.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(legendColors[index])
                    .frame(width: 9, height: 9)
            }
            Text("More")
                .font(.system(size: 8, weight: .heavy, design: .rounded))
                .foregroundColor(.lumiMuted)
                .lineLimit(1)
                .frame(width: 26, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var legendColors: [Color] {
        [.lumiRule, .lumiRed, .lumiOrange, .lumiYellow, .lumiGreen]
    }

    private func calendarColor(readCount: Int, totalStudents: Int) -> Color {
        if readCount <= 0 { return .lumiRule }
        let fraction = totalStudents > 0 ? Double(readCount) / Double(totalStudents) : 1
        if fraction <= 0.25 { return .lumiRed }
        if fraction <= 0.50 { return .lumiOrange }
        if fraction <= 0.75 { return .lumiYellow }
        return .lumiGreen
    }

    private var title: String {
        switch entry.kind {
        case .today: return "Class today"
        case .topReaders: return "Top Readers"
        case .readingCalendar: return "Calendar"
        }
    }

    private var tapURL: URL {
        URL(string: "lumi://widget/teacher?homeWidget=1&teacherWidget=\(entry.kind.rawValue)")!
    }
}

// MARK: - Preview

@available(iOS 17.0, *)
#Preview(as: .systemSmall) {
    LumiWidget()
} timeline: {
    LumiWidgetEntry.placeholder
    LumiWidgetEntry(
        date: Date(),
        studentId: "abc",
        firstName: "Sophie",
        characterId: "green_lumi",
        currentStreak: 13,
        minutesReadToday: 20,
        targetMinutes: 20,
        loggedToday: true,
        displayMode: .celebrating
    )
    LumiWidgetEntry(
        date: Date(),
        studentId: "abc",
        firstName: "Lily",
        characterId: "lumi_cat",
        currentStreak: 4,
        minutesReadToday: 0,
        targetMinutes: 20,
        loggedToday: false,
        displayMode: .streakAtRisk
    )
}
