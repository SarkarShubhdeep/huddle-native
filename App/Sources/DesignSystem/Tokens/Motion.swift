import SwiftUI

enum Motion {
    /// The one spring the app uses: 0.35 s, bounce 0.15.
    static let spring = Animation.spring(duration: 0.35, bounce: 0.15)

    /// The spring, or no animation when Reduce Motion is on.
    static func spring(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : spring
    }
}

private struct SpringOnChange<Value: Equatable>: ViewModifier {
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(Motion.spring(reduceMotion: reduceMotion), value: value)
    }
}

extension View {
    /// Animates changes to `value` with the app spring, unless Reduce Motion is on.
    func springAnimation<Value: Equatable>(value: Value) -> some View {
        modifier(SpringOnChange(value: value))
    }
}
