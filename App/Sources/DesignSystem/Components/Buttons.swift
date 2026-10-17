import SwiftUI

/// Text buttons. The primary action on a screen is the one solid lime capsule;
/// everything else is quieter.
struct HNButtonStyle: ButtonStyle {
    enum Role {
        /// Solid lime capsule. One per screen.
        case primary
        /// A raised neutral capsule ("Take a break").
        case secondary
        /// Red text with no fill ("End day"), so it's never pressed by accident.
        case destructive
        /// Lime text with no fill ("Change server", "Clear").
        case quiet
    }

    enum Size {
        /// 54 pt, full width. The hero action.
        case large
        /// 44 pt, sized to its label.
        case regular
        /// 30 pt, for inline actions such as Retry in a banner.
        case small
    }

    var role: Role = .primary
    var size: Size = .regular

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .foregroundStyle(foreground)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, Spacing.xs)
            .frame(maxWidth: size == .large ? .infinity : nil, minHeight: minHeight)
            .background(background, in: Capsule())
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .springAnimation(value: configuration.isPressed)
    }

    private var font: Font {
        switch size {
        case .large: .headline
        case .regular: .subheadline.weight(.semibold)
        case .small: .footnote.weight(.semibold)
        }
    }

    private var minHeight: CGFloat {
        switch size {
        case .large: 54
        case .regular: 44
        case .small: 30
        }
    }

    private var horizontalPadding: CGFloat {
        switch size {
        case .large: Spacing.xl
        case .regular: Spacing.xl
        case .small: Spacing.m
        }
    }

    private var foreground: Color {
        switch role {
        case .primary: Palette.onLime
        case .secondary: Palette.textPrimary
        case .destructive: Palette.destructive
        case .quiet: Palette.limeText
        }
    }

    private var background: Color {
        switch role {
        case .primary: Palette.lime
        case .secondary: Palette.surfaceRaised
        case .destructive, .quiet: .clear
        }
    }
}

/// Round icon-only buttons: play/pause on a ticket, "new ticket" in a header.
/// Callers must give the button an accessibility label.
struct HNIconButtonStyle: ButtonStyle {
    enum Role { case primary, secondary }

    var role: Role = .secondary
    var diameter: CGFloat = 40

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: diameter * 0.36, weight: .bold))
            .foregroundStyle(role == .primary ? Palette.onLime : Palette.textPrimary)
            .frame(width: diameter, height: diameter)
            .background(role == .primary ? Palette.lime : Palette.fill, in: Circle())
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Circle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .springAnimation(value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == HNButtonStyle {
    static var primary: HNButtonStyle { HNButtonStyle(role: .primary) }
    static var primaryLarge: HNButtonStyle { HNButtonStyle(role: .primary, size: .large) }
    static var secondary: HNButtonStyle { HNButtonStyle(role: .secondary) }
    static var secondaryLarge: HNButtonStyle { HNButtonStyle(role: .secondary, size: .large) }
    static var destructive: HNButtonStyle { HNButtonStyle(role: .destructive) }
    static var quiet: HNButtonStyle { HNButtonStyle(role: .quiet) }
}

struct ButtonsPreview: View {
    var body: some View {
        VStack(spacing: Spacing.l) {
            Button("Start day") {}.buttonStyle(.primaryLarge)
            Button("Take a break") {}.buttonStyle(.secondaryLarge)
            Button("End day") {}.buttonStyle(.destructive)
            HStack {
                Button("Try again") {}.buttonStyle(.primary)
                Button("Change server") {}.buttonStyle(.quiet)
                Button("Retry") {}.buttonStyle(HNButtonStyle(role: .secondary, size: .small))
            }
            HStack(spacing: Spacing.m) {
                Button("Pause ticket timer", systemImage: "pause.fill") {}
                    .labelStyle(.iconOnly)
                    .buttonStyle(HNIconButtonStyle(role: .secondary))
                Button("Start timer", systemImage: "play.fill") {}
                    .labelStyle(.iconOnly)
                    .buttonStyle(HNIconButtonStyle(role: .primary))
                Button("New ticket", systemImage: "plus") {}
                    .labelStyle(.iconOnly)
                    .buttonStyle(HNIconButtonStyle(role: .primary, diameter: 36))
                Button("Disabled") {}.buttonStyle(.primary).disabled(true)
            }
        }
        .padding(Spacing.margin)
        .frame(maxHeight: .infinity)
        .background(Palette.surface)
    }
}

#Preview("Light") { ButtonsPreview() }
#Preview("Dark") { ButtonsPreview().preferredColorScheme(.dark) }
