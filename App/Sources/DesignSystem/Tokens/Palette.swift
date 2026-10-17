import SwiftUI

/// The color tokens from DESIGN.md. Each one is a light/dark color set in
/// `Assets.xcassets/Palette`, so the system resolves the appearance for us.
enum Palette {
    // Surfaces
    /// Screen background behind content.
    static let canvas = Color("Canvas")
    /// Cards, sheets and the Now hero.
    static let surface = Color("Surface")
    /// Tiles and quiet buttons that sit on a surface.
    static let surfaceRaised = Color("SurfaceRaised")
    /// Unselected filter pills and segmented backgrounds.
    static let fill = Color("Fill")

    // Text
    static let textPrimary = Color("TextPrimary")
    static let textSecondary = Color("TextSecondary")
    /// Edge-to-edge list separators.
    static let hairline = Color("Hairline")

    // Accent: Graphite + Lime
    /// The solid accent fill. Always paired with `onLime` for text on top.
    static let lime = Color("Lime")
    static let onLime = Color("OnLime")
    /// Lime-colored text and icons: dark olive on light, lime on dark.
    static let limeText = Color("LimeText")
    /// Tinted backgrounds for the working chip, selected pills and avatars.
    static let limeSoft = Color("LimeSoft")

    // Status
    static let breakText = Color("BreakText")
    static let breakSoft = Color("BreakSoft")
    static let done = Color("Done")
    static let doneSoft = Color("DoneSoft")
    static let destructive = Color("Destructive")

    /// Inactive week bars.
    static let bar = Color("Bar")
}
