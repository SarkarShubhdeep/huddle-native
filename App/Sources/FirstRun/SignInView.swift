import HuddleKit
import OSLog
import SwiftUI

/// First run, step 2: email and password, with errors shown inline in plain words.
struct SignInView: View {
    let endpoint: ServerEndpoint
    let kind: ServerKind
    var initialEmail = ""
    /// A note shown before you try, e.g. that the session expired.
    var notice: String?
    var signIn: (String, String) async throws -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var error: String?
    @State private var isSigningIn = false
    @FocusState private var focused: Field?

    private enum Field { case email, password }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty && !isSigningIn
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("Sign in")
                        .font(Typography.largeTitle)
                        .foregroundStyle(Palette.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text("Use the email and password you use for TimeHuddle.")
                        .font(.body)
                        .foregroundStyle(Palette.textSecondary)
                }
                .padding(.horizontal, Spacing.xl)

                EdgeToEdgeList(separatorInset: Spacing.xl) {
                    fieldRow("Email") {
                        TextField("Email", text: $email, prompt: Text(verbatim: "you@company.com").foregroundStyle(Palette.textSecondary.opacity(0.6)))
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focused, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { focused = .password }
                    }
                    fieldRow("Password") {
                        SecureField("Password", text: $password, prompt: Text("Required").foregroundStyle(Palette.textSecondary.opacity(0.6)))
                            .textContentType(.password)
                            .focused($focused, equals: .password)
                            .submitLabel(.go)
                            .onSubmit(submit)
                    }
                }

                if let error {
                    InlineError(message: error)
                        .padding(.horizontal, Spacing.margin)
                        .transition(.opacity)
                }
            }
            .padding(.top, Spacing.l)
            .padding(.bottom, Spacing.l)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.canvas)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button(action: submit) {
                    if isSigningIn { ProgressView().tint(Palette.onLime) } else { Text("Sign in") }
                }
                .buttonStyle(.primaryLarge)
                .disabled(!canSubmit)
                Text("You stay signed in for 30 days. The token is kept in the iOS Keychain.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Spacing.margin)
            .padding(.bottom, Spacing.s)
            .background(Palette.canvas)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ServerBadge(endpoint: endpoint, kind: kind)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .springAnimation(value: error)
        .onAppear {
            if email.isEmpty { email = initialEmail }
            if error == nil { error = notice }
            focused = email.isEmpty ? .email : .password
        }
        .onChange(of: email) { error = nil }
        .onChange(of: password) { error = nil }
    }

    private func fieldRow<F: View>(_ label: String, @ViewBuilder field: () -> F) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(label).font(.footnote).foregroundStyle(Palette.textSecondary)
            field()
                .font(.body)
                .foregroundStyle(Palette.textPrimary)
                .padding(.vertical, Spacing.xs)
                .accessibilityLabel(label)
        }
        .padding(.vertical, Spacing.m)
        .padding(.horizontal, Spacing.xl)
        .contentShape(Rectangle())
    }

    private static let log = Logger(subsystem: "HuddleNative", category: "SignIn")

    private func submit() {
        guard canSubmit else { return }
        focused = nil
        isSigningIn = true
        error = nil
        Task {
            do {
                try await signIn(email, password)
            } catch {
                Self.log.error("Sign-in failed: \(String(describing: error), privacy: .public)")
                // Keep the password so a typo in the email can be fixed; the
                // message clears as soon as either field is edited.
                self.error = (error as? LocalizedError)?.errorDescription ?? "Sign-in failed. Try again."
                focused = .password
            }
            isSigningIn = false
        }
    }
}

/// A red, inline error message.
struct InlineError: View {
    let message: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.circle").accessibilityHidden(true)
            Text(message).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.subheadline)
        .foregroundStyle(Palette.destructive)
        .padding(.vertical, Spacing.m)
        .padding(.horizontal, 14)
        .background(Palette.destructiveSoft, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
    }
}

/// "192.168.1.24 · This Wi-Fi", with a green dot: which server you're signing in to.
struct ServerBadge: View {
    let endpoint: ServerEndpoint
    let kind: ServerKind

    var body: some View {
        HStack(spacing: Spacing.s) {
            Circle().fill(Palette.done).frame(width: 7, height: 7)
            Text("\(endpoint.baseURL.host() ?? "") · \(kind.title)")
                .lineLimit(1)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Palette.textSecondary)
        .padding(.horizontal, Spacing.m)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Server: \(endpoint.baseURL.host() ?? ""), \(kind.title)")
    }
}

#Preview("Light") {
    NavigationStack {
        SignInView(endpoint: ServerEndpoint("192.168.1.24")!, kind: .thisWiFi, initialEmail: "you@company.com") { _, _ in
            throw LoginError.invalidCredentials
        }
    }
}

#Preview("Dark") {
    NavigationStack {
        SignInView(endpoint: ServerEndpoint("192.168.1.24")!, kind: .thisWiFi) { _, _ in
            throw LoginError.suspended("This account is suspended. Ask your team admin.")
        }
    }
    .preferredColorScheme(.dark)
}
