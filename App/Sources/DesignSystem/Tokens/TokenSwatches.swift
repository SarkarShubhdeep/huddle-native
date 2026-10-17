import SwiftUI

/// Every token on one screen, for checking against the design canvas.
struct TokenSwatches: View {
    private let colors: [(String, Color)] = [
        ("Canvas", Palette.canvas), ("Surface", Palette.surface), ("Surface raised", Palette.surfaceRaised),
        ("Fill", Palette.fill), ("Text", Palette.textPrimary), ("Text secondary", Palette.textSecondary),
        ("Hairline", Palette.hairline), ("Lime", Palette.lime), ("On lime", Palette.onLime),
        ("Lime text", Palette.limeText), ("Lime soft", Palette.limeSoft), ("Break text", Palette.breakText),
        ("Break soft", Palette.breakSoft), ("Done", Palette.done), ("Done soft", Palette.doneSoft),
        ("Destructive", Palette.destructive), ("Bar", Palette.bar),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: Spacing.s)], spacing: Spacing.s) {
                ForEach(colors, id: \.0) { name, color in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        RoundedRectangle(cornerRadius: Radius.control)
                            .fill(color)
                            .frame(height: 44)
                            .overlay(RoundedRectangle(cornerRadius: Radius.control).stroke(Palette.hairline))
                        Text(name).font(Typography.caption).foregroundStyle(Palette.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HeroTimeText(text: "3:42:18")
                Text("0:42:10").font(Typography.time(.title3))
                Text("Large title").font(Typography.largeTitle)
                Text("Section title").font(Typography.sectionTitle)
                Text("Body text").font(Typography.body)
                Text("SHIFT").font(Typography.microLabel).foregroundStyle(Palette.limeText)
            }
            .foregroundStyle(Palette.textPrimary)
        }
        .padding(Spacing.margin)
    }
}

#Preview("Light") {
    ScrollView { TokenSwatches() }.background(Palette.canvas)
}

#Preview("Dark") {
    ScrollView { TokenSwatches() }.background(Palette.canvas).preferredColorScheme(.dark)
}
