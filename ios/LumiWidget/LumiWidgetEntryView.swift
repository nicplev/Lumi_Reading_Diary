import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Colours (mirrors Lumi Dart theme)

private extension Color {
    static let lumiRosePink           = Color(red: 1.00, green: 0.53, blue: 0.60)  // #FF8698
    static let lumiRosePinkAccessible = Color(red: 0.784, green: 0.278, blue: 0.361) // #C8475C
    static let lumiPeach              = Color(red: 1.00, green: 0.67, blue: 0.57)  // #FFAB91
    static let lumiMint               = Color(red: 0.82, green: 0.92, blue: 0.75)  // #D2EBBF
    static let lumiGreen              = Color(red: 0.30, green: 0.70, blue: 0.42)  // celebrating ink
    static let lumiOrange             = Color(red: 1.00, green: 0.55, blue: 0.35)  // #FF8B5A
    static let lumiAmberDeep          = Color(red: 0.85, green: 0.45, blue: 0.10)  // at-risk ink
    static let lumiCharcoal           = Color(red: 0.07, green: 0.07, blue: 0.07)  // #121211
    static let lumiOffWhite           = Color(red: 0.97, green: 0.97, blue: 0.95)  // #F8F8F3
    static let lumiAmber              = Color(red: 1.00, green: 0.76, blue: 0.28)  // #FFC247
}

// MARK: - Main View

struct LumiWidgetEntryView: View {
    var entry: LumiWidgetEntry

    var body: some View {
        ZStack {
            backgroundView
            contentView
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
        }
        .widgetURL(tapURL)
    }

    // MARK: Background — two-tone Lumi gradients per mode

    @ViewBuilder
    private var backgroundView: some View {
        switch entry.displayMode {
        case .reminder:
            LinearGradient(
                colors: [Color.lumiOffWhite, Color.lumiRosePink.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .celebrating:
            LinearGradient(
                colors: [Color.lumiMint.opacity(0.55), Color.lumiOffWhite],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .streakAtRisk:
            LinearGradient(
                colors: [Color.lumiAmber.opacity(0.35), Color.lumiOrange.opacity(0.15)],
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
            Spacer(minLength: 6)
            heroBlock
                .frame(maxWidth: .infinity, alignment: .center)
            Spacer(minLength: 6)
            ctaButton
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: Header — avatar + name/subtitle + streak chip

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 8) {
            avatar
            VStack(alignment: .leading, spacing: -1) {
                Text(entry.firstName)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.lumiCharcoal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(modeSubtitle)
                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                    .tracking(0.4)
                    .textCase(.uppercase)
                    .foregroundColor(subtitleColor)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            // In celebrating mode the streak moves into the hero, so we hide the chip here
            if entry.displayMode != .celebrating && entry.currentStreak > 0 {
                streakChip
            }
        }
    }

    private var avatar: some View {
        Image(entry.characterId)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 30, height: 30)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
            )
            .shadow(color: Color.lumiCharcoal.opacity(0.10), radius: 3, x: 0, y: 1)
    }

    private var streakChip: some View {
        HStack(spacing: 3) {
            Text("🔥")
                .font(.system(size: 10))
            Text("\(entry.currentStreak)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.lumiCharcoal)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.92))
        )
        .overlay(
            Capsule()
                .stroke(Color.lumiCharcoal.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: Color.lumiCharcoal.opacity(0.06), radius: 2, x: 0, y: 1)
    }

    private var modeSubtitle: String {
        switch entry.displayMode {
        case .reminder:      return "Today's read"
        case .celebrating:   return "Done for today"
        case .streakAtRisk:  return "Streak at risk"
        }
    }

    private var subtitleColor: Color {
        switch entry.displayMode {
        case .reminder:      return Color.lumiCharcoal.opacity(0.45)
        case .celebrating:   return Color.lumiGreen.opacity(0.85)
        case .streakAtRisk:  return Color.lumiAmberDeep
        }
    }

    // MARK: Hero — mode-specific focal element

    @ViewBuilder
    private var heroBlock: some View {
        switch entry.displayMode {
        case .reminder:
            reminderHero
        case .celebrating:
            celebratingHero
        case .streakAtRisk:
            streakAtRiskHero
        }
    }

    private var reminderHero: some View {
        let progress = entry.targetMinutes > 0
            ? min(Double(entry.minutesReadToday) / Double(entry.targetMinutes), 1.0)
            : 0.0

        return ZStack {
            Circle()
                .stroke(Color.lumiRosePink.opacity(0.18), lineWidth: 5)
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(
                    LinearGradient(
                        colors: [Color.lumiRosePink, Color.lumiPeach],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: progress)

            VStack(spacing: -1) {
                Text("\(entry.minutesReadToday)/\(entry.targetMinutes)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.lumiCharcoal)
                Text("min")
                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                    .foregroundColor(.lumiCharcoal.opacity(0.5))
            }
        }
        .frame(width: 56, height: 56)
    }

    private var celebratingHero: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.lumiMint, Color(red: 0.65, green: 0.88, blue: 0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)
                    .shadow(color: Color.lumiGreen.opacity(0.25), radius: 6, x: 0, y: 2)
                Image(systemName: "checkmark")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
            }
            if entry.currentStreak > 0 {
                HStack(spacing: 3) {
                    Text("🔥")
                        .font(.system(size: 10))
                    Text("\(entry.currentStreak) day\(entry.currentStreak == 1 ? "" : "s")")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.lumiCharcoal)
                }
            }
        }
    }

    private var streakAtRiskHero: some View {
        VStack(spacing: 1) {
            Text("\(entry.currentStreak)")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundColor(.lumiCharcoal)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Rectangle()
                .fill(Color.lumiAmberDeep.opacity(0.7))
                .frame(width: 22, height: 1.5)
            Text("day streak")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundColor(.lumiAmberDeep)
                .tracking(0.3)
        }
    }

    // MARK: CTA Button

    // iOS 17+: reminder & at-risk fire LogReadingIntent in place.
    // iOS 14–16: whole-widget tap routes through widgetURL.
    @ViewBuilder
    private var ctaButton: some View {
        if #available(iOS 17.0, *), entry.displayMode != .celebrating {
            Button(intent: LogReadingIntent(studentId: entry.studentId)) {
                ctaLabelView
            }
            .buttonStyle(.plain)
        } else {
            ctaLabelView
        }
    }

    private var ctaLabelView: some View {
        HStack(spacing: 4) {
            Image(systemName: ctaIcon)
                .font(.system(size: 9, weight: .bold))
            Text(ctaLabel)
                .font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: ctaGradient,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        )
        .shadow(color: ctaShadow, radius: 4, x: 0, y: 2)
    }

    private var ctaLabel: String {
        switch entry.displayMode {
        case .reminder:     return "Log reading"
        case .celebrating:  return "View progress"
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

    private var ctaGradient: [Color] {
        switch entry.displayMode {
        case .reminder:
            return [Color.lumiRosePinkAccessible, Color.lumiPeach]
        case .celebrating:
            return [Color.lumiGreen, Color(red: 0.20, green: 0.60, blue: 0.35)]
        case .streakAtRisk:
            return [Color.lumiOrange, Color.lumiAmberDeep]
        }
    }

    private var ctaShadow: Color {
        switch entry.displayMode {
        case .reminder:     return Color.lumiRosePinkAccessible.opacity(0.30)
        case .celebrating:  return Color.lumiGreen.opacity(0.30)
        case .streakAtRisk: return Color.lumiOrange.opacity(0.35)
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
