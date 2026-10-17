import SwiftUI

/// The color family that says where you are: grey off the clock, lime while
/// working, amber on a break, green once the day is done.
enum Tone: Sendable {
    case neutral, working, onBreak, done

    var foreground: Color {
        switch self {
        case .neutral: Palette.textSecondary
        case .working: Palette.limeText
        case .onBreak: Palette.breakText
        case .done: Palette.done
        }
    }

    var background: Color {
        switch self {
        case .neutral: Palette.surfaceRaised
        case .working: Palette.limeSoft
        case .onBreak: Palette.breakSoft
        case .done: Palette.doneSoft
        }
    }
}

/// A capsule label with a tone: "Working", "On break", and the Plan and
/// Wrap-up badges on posts.
struct StatusChip: View {
    enum Style {
        /// With a leading dot, for shift state.
        case status
        /// Smaller and bolder, no dot, for post kinds.
        case badge
    }

    let label: String
    let tone: Tone
    var style: Style = .status

    var body: some View {
        HStack(spacing: 6) {
            if style == .status {
                Circle()
                    .fill(tone.foreground)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
            }
            Text(label)
        }
        .font(style == .status ? .footnote.weight(.semibold) : .caption.weight(.bold))
        .foregroundStyle(tone.foreground)
        .padding(.vertical, style == .status ? 5 : 4)
        .padding(.horizontal, style == .status ? 10 : 9)
        .background(tone.background, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

struct StatusChipPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack {
                StatusChip(label: "Off the clock", tone: .neutral)
                StatusChip(label: "Working", tone: .working)
            }
            HStack {
                StatusChip(label: "On break", tone: .onBreak)
                StatusChip(label: "Day done", tone: .done)
            }
            HStack {
                StatusChip(label: "Plan", tone: .working, style: .badge)
                StatusChip(label: "Wrap-up", tone: .done, style: .badge)
            }
        }
        .padding(Spacing.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.surface)
    }
}

#Preview("Light") { StatusChipPreview() }
#Preview("Dark") { StatusChipPreview().preferredColorScheme(.dark) }
