#if DEBUG
import SwiftUI

/// Debug-only screen that shows every design-system component, so they can be
/// screenshotted in the Simulator and compared with the design canvas.
/// Replaced as the app's root by the first-run flow in Step 4.
///
/// Launch with `-showcase <id>` to open one showcase directly.
struct ComponentGallery: View {
    enum Showcase: String, CaseIterable, Identifiable {
        case tokens, buttons, chips, rows, states

        var id: String { rawValue }

        var title: String {
            switch self {
            case .tokens: "Tokens"
            case .buttons: "Buttons"
            case .chips: "Status chips"
            case .rows: "Edge-to-edge rows"
            case .states: "Banner and states"
            }
        }

        @ViewBuilder var view: some View {
            switch self {
            case .tokens: ScrollView { TokenSwatches() }.background(Palette.canvas)
            case .buttons: ButtonsPreview()
            case .chips: StatusChipPreview()
            case .rows: RowsPreview()
            case .states: StatesPreview()
            }
        }
    }

    @State private var path: [Showcase] = UserDefaults.standard.string(forKey: "showcase")
        .flatMap(Showcase.init(rawValue:)).map { [$0] } ?? []

    var body: some View {
        NavigationStack(path: $path) {
            List(Showcase.allCases) { showcase in
                NavigationLink(showcase.title, value: showcase)
            }
            .navigationTitle("Components")
            .navigationDestination(for: Showcase.self) { showcase in
                showcase.view
                    .navigationTitle(showcase.title)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

#Preview("Light") { ComponentGallery() }
#Preview("Dark") { ComponentGallery().preferredColorScheme(.dark) }
#endif
