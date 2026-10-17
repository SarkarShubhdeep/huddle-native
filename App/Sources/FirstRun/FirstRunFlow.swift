import HuddleKit
import SwiftUI

/// Server picker → sign in.
struct FirstRunFlow: View {
    @Environment(AppModel.self) private var model
    /// Why you're signed out, if it wasn't your choice.
    var reason: SessionStore.SignOutReason?

    private struct Destination: Hashable {
        let endpoint: ServerEndpoint
        let kind: ServerKind
    }

    @State private var path: [Destination] = []

    var body: some View {
        NavigationStack(path: $path) {
            ServerPickerView { endpoint, kind in
                path = [Destination(endpoint: endpoint, kind: kind)]
            }
            .navigationDestination(for: Destination.self) { destination in
                SignInView(
                    endpoint: destination.endpoint,
                    kind: destination.kind,
                    initialEmail: model.lastEmail,
                    notice: reason == .expired ? "Your session expired. Sign in again." : nil
                ) { email, password in
                    try await model.signIn(email: email, password: password, endpoint: destination.endpoint)
                }
            }
        }
        .tint(Palette.limeText)
        .onAppear {
            // After an expired session, go straight back to signing in on the same server.
            let choice = ServerChoice.load()
            if reason == .expired, path.isEmpty, let endpoint = choice.endpoint {
                path = [Destination(endpoint: endpoint, kind: choice.kind)]
            }
        }
    }
}
