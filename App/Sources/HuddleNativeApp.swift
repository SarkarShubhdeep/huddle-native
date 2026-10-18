import HuddleKit
import SwiftUI

@main
struct HuddleNativeApp: App {
    @State private var model = AppModel()
    @State private var releaseNotes = ReleaseNotesStore()

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "gallery") {
                // Launch with `-gallery YES` for the component gallery.
                ComponentGallery()
            } else {
                RootView().environment(model).environment(releaseNotes)
            }
            #else
            RootView().environment(model).environment(releaseNotes)
            #endif
        }
    }
}

/// Restoring → first run, or the signed-in app.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch model.session.state {
            case .restoring:
                AppMark(size: 72)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Palette.canvas)
            case let .signedOut(reason):
                FirstRunFlow(reason: reason)
            case .signedIn:
                MainShell()
            }
        }
        .springAnimation(value: model.session.state)
        .task { await model.start() }
        .onChange(of: scenePhase) { _, phase in
            // Coming back to the app refreshes what's on screen.
            if phase == .active, model.session.session != nil {
                Task { await model.refreshTeams() }
            }
        }
    }
}
