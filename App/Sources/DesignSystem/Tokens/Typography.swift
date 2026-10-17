import SwiftUI

/// Type roles. Text uses the system text styles so it follows Dynamic Type;
/// times use SF Rounded with tabular digits so a ticking clock never jitters.
enum Typography {
    static let largeTitle = Font.largeTitle.bold()
    static let sectionTitle = Font.title3.bold()
    static let headline = Font.headline
    static let body = Font.body
    static let callout = Font.callout
    static let subheadline = Font.subheadline
    static let footnote = Font.footnote
    static let caption = Font.caption
    /// Uppercase micro labels, like "SHIFT" in the timer strip.
    static let microLabel = Font.caption2.weight(.bold)

    /// A time in SF Rounded with tabular digits, scaled with Dynamic Type.
    static func time(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .rounded, weight: weight).monospacedDigit()
    }
}

/// The big hero time ("3:42:18"). 72 pt at the default text size, scaled with
/// Dynamic Type, and allowed to shrink to fit rather than wrap.
struct HeroTimeText: View {
    let text: String
    var size: CGFloat = 72

    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1

    var body: some View {
        Text(text)
            .font(.system(size: size * scale, weight: .semibold, design: .rounded).monospacedDigit())
            .tracking(-size / 36)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .contentTransition(.numericText())
    }
}
