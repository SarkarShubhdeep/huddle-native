import HuddleKit
import SwiftUI

/// The Now screen's card: one card, four states, always one obvious action.
/// No rings or bars; the time is the hero, with a few plain facts under it.
struct NowHero: View {
    struct Fact: Hashable {
        let label: String
        let value: String
    }

    let phase: ShiftPhase
    /// "3:42:18" while working, "0:12:40" on a break, "7:51" for a finished day.
    let time: String
    /// What VoiceOver reads for the time, e.g. "3 hours, 42 minutes".
    var timeAccessibilityLabel: String?
    /// "Since 9:02 AM", "Your ticket timer is paused."
    let subtitle: String
    let facts: [Fact]
    let primaryTitle: String
    var primaryAction: () -> Void = {}
    /// Shown under the primary action while working.
    var onEndDay: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                StatusChip(label: chipLabel, tone: tone)
                Spacer()
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tone.foreground)
                    .frame(width: 44, height: 44)
                    .background(tone.background, in: RoundedRectangle(cornerRadius: Radius.tile))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HeroTimeText(text: time)
                    .foregroundStyle(Palette.textPrimary)
                    .accessibilityLabel(timeAccessibilityLabel ?? time)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
            }
            factsView
            VStack(spacing: 0) {
                Button(primaryTitle, action: primaryAction)
                    .buttonStyle(HNButtonStyle(role: primaryIsAccent ? .primary : .secondary, size: .large))
                if let onEndDay, phase == .working {
                    Button("End day", action: onEndDay)
                        .buttonStyle(.destructive)
                        .padding(.top, Spacing.xs)
                }
            }
        }
        .padding(Spacing.xl)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.hero))
        .springAnimation(value: phase)
    }

    /// Three tiles side by side; a plain list when large text won't fit them.
    private var factsView: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.s) {
                ForEach(facts, id: \.self) { fact in
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(fact.label).font(.caption).foregroundStyle(Palette.textSecondary)
                        Text(fact.value).font(.callout.weight(.semibold)).monospacedDigit()
                    }
                    .lineLimit(1)
                    .fixedSize()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                    .padding(.horizontal, Spacing.m)
                    .background(Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.tile))
                    .accessibilityElement(children: .combine)
                }
            }
            VStack(spacing: 0) {
                ForEach(facts, id: \.self) { fact in
                    let layout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xxs))
                        : AnyLayout(HStackLayout())
                    layout {
                        Text(fact.label).foregroundStyle(Palette.textSecondary)
                        Spacer(minLength: 0)
                        Text(fact.value).fontWeight(.semibold).monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.subheadline)
                    .padding(.vertical, 7)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.xs)
            .background(Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.tile))
        }
        .foregroundStyle(Palette.textPrimary)
    }

    private var tone: Tone {
        switch phase {
        case .idle: .neutral
        case .working: .working
        case .onBreak: .onBreak
        case .ended: .done
        }
    }

    private var chipLabel: String {
        switch phase {
        case .idle: "Off the clock"
        case .working: "Working"
        case .onBreak: "On break"
        case .ended: "Day done"
        }
    }

    private var icon: String {
        switch phase {
        case .idle: "sun.max"
        case .working: "clock"
        case .onBreak: "cup.and.saucer"
        case .ended: "checkmark"
        }
    }

    /// Starting and resuming are the accent action. While working, Break is
    /// primary but quiet, so you don't clock out by accident.
    private var primaryIsAccent: Bool { phase == .idle || phase == .onBreak }
}

/// The ticket being timed, under the hero: "Working on" or "Paused".
struct TicketTimerCard: View {
    let title: String
    let time: String
    var isPaused = false
    var onToggle: () -> Void = {}

    var body: some View {
        HStack(spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(isPaused ? "Paused" : "Working on")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(time)
                .font(Typography.time(.headline))
                .foregroundStyle(isPaused ? Palette.textSecondary : Palette.limeText)
                .contentTransition(.numericText())
            if !isPaused {
                Button("Pause ticket timer", systemImage: "pause.fill", action: onToggle)
                    .labelStyle(.iconOnly)
                    .buttonStyle(HNIconButtonStyle())
            }
        }
        .frame(minHeight: 52)
        .padding(.vertical, Spacing.xs)
        .padding(.leading, Spacing.l)
        .padding(.trailing, isPaused ? Spacing.l : Spacing.s)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Samples and previews

extension NowHero {
    /// The four canvas states, for previews and the gallery.
    static func sample(_ phase: ShiftPhase) -> NowHero {
        switch phase {
        case .idle:
            NowHero(phase: .idle, time: "0:00", subtitle: "Yesterday you worked 7h 48m.",
                    facts: [.init(label: "Yesterday", value: "7h 48m"), .init(label: "This week", value: "23h 24m"),
                            .init(label: "Open tickets", value: "4")],
                    primaryTitle: "Start day")
        case .working:
            NowHero(phase: .working, time: "3:42:18", timeAccessibilityLabel: "3 hours, 42 minutes",
                    subtitle: "Since 9:02 AM",
                    facts: [.init(label: "Started", value: "9:02 AM"), .init(label: "Breaks", value: "12m"),
                            .init(label: "Tickets", value: "3")],
                    primaryTitle: "Take a break", onEndDay: {})
        case .onBreak:
            NowHero(phase: .onBreak, time: "0:12:40", timeAccessibilityLabel: "12 minutes",
                    subtitle: "Your ticket timer is paused.",
                    facts: [.init(label: "Meal break in", value: "7 min"), .init(label: "Worked", value: "3h 42m"),
                            .init(label: "Since", value: "12:44 PM")],
                    primaryTitle: "Back to work")
        case .ended:
            NowHero(phase: .ended, time: "7:51", timeAccessibilityLabel: "7 hours, 51 minutes",
                    subtitle: "9:02 AM – 5:21 PM",
                    facts: [.init(label: "Unpaid meal", value: "28m"), .init(label: "Tickets", value: "4"),
                            .init(label: "Wrap-up", value: "Posted")],
                    primaryTitle: "See timesheet")
        }
    }
}

struct NowHeroPreview: View {
    var phases: [ShiftPhase] = [.idle, .working, .onBreak, .ended]

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.l) {
                ForEach(phases.indices, id: \.self) { index in
                    let phase = phases[index]
                    NowHero.sample(phase)
                    if phase == .working {
                        TicketTimerCard(title: "Fix login redirect on iPad", time: "0:42:10")
                    } else if phase == .onBreak {
                        TicketTimerCard(title: "Fix login redirect on iPad", time: "0:42:10", isPaused: true)
                    }
                }
            }
            .padding(Spacing.margin)
        }
        .background(Palette.canvas)
    }
}

#Preview("Light") { NowHeroPreview() }
#Preview("Dark") { NowHeroPreview().preferredColorScheme(.dark) }
