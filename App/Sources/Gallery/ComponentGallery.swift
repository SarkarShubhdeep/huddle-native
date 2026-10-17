#if DEBUG
import SwiftUI

/// Debug-only screen that shows every design-system component, so they can be
/// screenshotted in the Simulator and compared with the design canvas.
/// Replaced as the app's root by the first-run flow in Step 4.
struct ComponentGallery: View {
    var body: some View {
        ScrollView {
            TokenSwatches()
        }
        .background(Palette.canvas)
    }
}

#Preview("Light") { ComponentGallery() }
#Preview("Dark") { ComponentGallery().preferredColorScheme(.dark) }
#endif
