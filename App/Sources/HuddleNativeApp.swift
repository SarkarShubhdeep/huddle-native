import HuddleKit
import SwiftUI

@main
struct HuddleNativeApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            ComponentGallery()
            #else
            SkeletonView()
            #endif
        }
    }
}

/// Step 1 placeholder: proves the app, HuddleKit and Info.plist wiring work.
/// Replaced by the first-run flow in Step 4.
private struct SkeletonView: View {
    private let defaultServer = Bundle.main.object(forInfoDictionaryKey: "HNDefaultServerURL") as? String ?? ""

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.tint)
            Text("Huddle")
                .font(.largeTitle.bold())
            if let endpoint = ServerEndpoint(defaultServer) {
                Text(endpoint.baseURL.absoluteString)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

#Preview {
    SkeletonView()
}
