import SwiftUI

/// Liquid Glass for the controls layer only: floating buttons, the composer
/// toolbar, menus. Content never uses this.
///
/// With Reduce Transparency on, the glass becomes a solid surface with a
/// hairline edge, so text on it keeps full contrast.
private struct ControlGlass<S: Shape>: ViewModifier {
    let shape: S
    let interactive: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Palette.surface, in: shape)
                .overlay(shape.stroke(Palette.hairline, lineWidth: 1))
        } else {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        }
    }
}

extension View {
    /// Puts the view on control-layer glass, falling back to a solid surface under Reduce Transparency.
    func controlGlass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        modifier(ControlGlass(shape: shape, interactive: interactive))
    }

    /// Capsule-shaped control glass.
    func controlGlass(interactive: Bool = false) -> some View {
        modifier(ControlGlass(shape: Capsule(), interactive: interactive))
    }
}
