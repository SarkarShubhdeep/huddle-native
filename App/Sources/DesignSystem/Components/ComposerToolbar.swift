import SwiftUI

/// What the composer can apply. The rich editor itself arrives in Step 8;
/// this is the toolbar it will drive.
enum ComposerFormat: String, CaseIterable, Identifiable, Sendable {
    case bold, italic, strikethrough, bulletList, numberedList, checklist, mention

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bold: "Bold"
        case .italic: "Italic"
        case .strikethrough: "Strikethrough"
        case .bulletList: "Bulleted list"
        case .numberedList: "Numbered list"
        case .checklist: "Checklist"
        case .mention: "Mention a person or ticket"
        }
    }

    var systemImage: String {
        switch self {
        case .bold: "bold"
        case .italic: "italic"
        case .strikethrough: "strikethrough"
        case .bulletList: "list.bullet"
        case .numberedList: "list.number"
        case .checklist: "checklist"
        case .mention: "at"
        }
    }
}

/// The composer's formatting toolbar, on control-layer glass. Formats that
/// apply at the cursor show as selected.
struct ComposerToolbar: View {
    var active: Set<ComposerFormat> = []
    var onSelect: (ComposerFormat) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ComposerFormat.allCases) { format in
                let isOn = active.contains(format)
                Button(format.title, systemImage: format.systemImage) { onSelect(format) }
                    .labelStyle(.iconOnly)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isOn ? Palette.limeText : Palette.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(isOn ? Palette.limeSoft : .clear, in: Circle())
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
                    .focusable(false)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                    .springAnimation(value: isOn)
            }
        }
        .padding(.horizontal, Spacing.xs)
        .frame(height: 52)
        .controlGlass(interactive: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Formatting")
    }
}

// MARK: - Previews

struct ComposerToolbarPreview: View {
    @State private var active: Set<ComposerFormat> = [.bold, .mention]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text("Pairing on the iPad fix with **@Alex**")
                .font(.body)
                .foregroundStyle(Palette.textPrimary)
            Spacer()
            ComposerToolbar(active: active) { format in
                if active.contains(format) { active.remove(format) } else { active.insert(format) }
            }
        }
        .padding(Spacing.xl)
        .background(
            // Something under the glass, so the material has content to refract.
            LinearGradient(colors: [Palette.canvas, Palette.limeSoft], startPoint: .top, endPoint: .bottom)
        )
    }
}

#Preview("Light") { ComposerToolbarPreview() }
#Preview("Dark") { ComposerToolbarPreview().preferredColorScheme(.dark) }
