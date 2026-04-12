import SwiftUI
import WidgetKit

// MARK: - Colours (mirrors Lumi Dart theme)

private extension Color {
    static let lumiRosePink   = Color(red: 1.00, green: 0.53, blue: 0.60)  // #FF8698
    static let lumiMint       = Color(red: 0.82, green: 0.92, blue: 0.75)  // #D2EBBF
    static let lumiOrange     = Color(red: 1.00, green: 0.66, blue: 0.48)  // #FFA97C
    static let lumiCharcoal   = Color(red: 0.07, green: 0.07, blue: 0.07)  // #121211
    static let lumiOffWhite   = Color(red: 0.97, green: 0.97, blue: 0.95)  // #F8F8F3
    static let lumiAmber      = Color(red: 1.00, green: 0.76, blue: 0.28)  // #FFC247
}

// MARK: - Main View

struct LumiWidgetEntryView: View {
    var entry: LumiWidgetEntry

    var body: some View {
        // Link wraps the entire widget for iOS 14–16.
        // On iOS 17+ each Button sub-view can have its own Link/AppIntent.
        Link(destination: tapURL) {
            ZStack {
                backgroundView
                contentView
                    .padding(14)
            }
        }
        .widgetURL(tapURL)
    }

    // MARK: Background

    @ViewBuilder
    private var backgroundView: some View {
        switch entry.displayMode {
        case .reminder:
            Color.lumiOffWhite
        case .celebrating:
            LinearGradient(
                colors: [Color.lumiMint.opacity(0.6), Color.lumiOffWhite],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .streakAtRisk:
            LinearGradient(
                colors: [Color.lumiAmber.opacity(0.4), Color.lumiOffWhite],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    // MARK: Content

    @ViewBuilder
    private var contentView: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            Spacer(minLength: 4)
            switch entry.displayMode {
            case .reminder:
                reminderBody
            case .celebrating:
                celebratingBody
            case .streakAtRisk:
                streakAtRiskBody
            }
            Spacer(minLength: 6)
            ctaButton
        }
    }

    // MARK: Header

    private var headerRow: some View {
        HStack(alignment: .top) {
            characterImage
                .frame(width: 44, height: 44)
            Spacer()
            streakBadge
        }
    }

    private var characterImage: some View {
        Image(entry.characterId)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(Circle())
    }

    private var streakBadge: some View {
        HStack(spacing: 2) {
            Text("🔥")
                .font(.system(size: 13))
            Text("\(entry.currentStreak)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.lumiCharcoal)
        }
    }

    // MARK: Mode Bodies

    private var reminderBody: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.firstName)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.lumiCharcoal)
                .lineLimit(1)
            progressArc
            Text("0 / \(entry.targetMinutes) min")
                .font(.system(size: 10, design: .rounded))
                .foregroundColor(.secondary)
        }
    }

    private var celebratingBody: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.firstName)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.lumiCharcoal)
                .lineLimit(1)
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 14))
                Text(entry.minutesReadToday > 0
                     ? "\(entry.minutesReadToday) min read!"
                     : "Read today! ✓")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.lumiCharcoal)
            }
        }
    }

    private var streakAtRiskBody: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Don't break it!")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.lumiCharcoal)
            Text("\(entry.currentStreak) days at stake")
                .font(.system(size: 10, design: .rounded))
                .foregroundColor(.secondary)
        }
    }

    // MARK: Progress Arc

    private var progressArc: some View {
        let progress = entry.targetMinutes > 0
            ? min(Double(entry.minutesReadToday) / Double(entry.targetMinutes), 1.0)
            : 0.0

        return ZStack {
            Circle()
                .stroke(Color.lumiRosePink.opacity(0.2), lineWidth: 4)
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(Color.lumiRosePink, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: progress)
        }
        .frame(width: 28, height: 28)
    }

    // MARK: CTA Button

    private var ctaButton: some View {
        Text(ctaLabel)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(ctaColor)
            .clipShape(Capsule())
    }

    private var ctaLabel: String {
        switch entry.displayMode {
        case .reminder:    return "Log Reading"
        case .celebrating: return "Great work! →"
        case .streakAtRisk: return "Log Now!"
        }
    }

    private var ctaColor: Color {
        switch entry.displayMode {
        case .reminder:    return .lumiRosePink
        case .celebrating: return .green
        case .streakAtRisk: return .lumiOrange
        }
    }

    // MARK: Deep Link URL

    private var tapURL: URL {
        let action = entry.loggedToday ? "home" : "log"
        return URL(string: "lumi://widget/\(action)?childId=\(entry.studentId)")
            ?? URL(string: "lumi://widget/home")!
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
        characterId: "character_default",
        currentStreak: 13,
        minutesReadToday: 20,
        targetMinutes: 20,
        loggedToday: true,
        displayMode: .celebrating
    )
    LumiWidgetEntry(
        date: Date(),
        studentId: "abc",
        firstName: "Sophie",
        characterId: "character_default",
        currentStreak: 12,
        minutesReadToday: 0,
        targetMinutes: 20,
        loggedToday: false,
        displayMode: .streakAtRisk
    )
}
