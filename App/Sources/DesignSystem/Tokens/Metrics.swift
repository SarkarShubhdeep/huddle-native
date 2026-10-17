import SwiftUI

/// A 4-pt grid. Screens use `margin` on both sides.
enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    /// Leading and trailing screen margin.
    static let margin: CGFloat = 16
}

/// Corner radii from DESIGN.md. Capsules use `Capsule()` rather than a number.
enum Radius {
    /// Small tiles (fact tiles, image attachments, ticket chips).
    static let tile: CGFloat = 14
    /// Buttons, fields and other controls.
    static let control: CGFloat = 12
    /// Cards.
    static let card: CGFloat = 20
    /// The Now hero and sheets.
    static let hero: CGFloat = 28
}
