import HuddleKit
import SwiftUI

/// First run, step 1: "Where's your team?" Pick a server and see, before
/// going on, whether a TimeHuddle backend answers there.
struct ServerPickerView: View {
    var onContinue: (ServerEndpoint, ServerKind) -> Void
    var probe = ServerProbe()

    @State private var choice = ServerChoice.load()
    @State private var status: ConnectionStatus = .idle
    @FocusState private var focused: Field?

    private enum Field { case host, port, custom }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                header
                EdgeToEdgeList(separatorInset: 60) {
                    ForEach(AppConfig.availableKinds) { kind in
                        row(kind)
                    }
                }
                Text("The first time, iOS asks to find devices on your local network. Allow it, or Huddle can’t reach your Mac.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, Spacing.xl)
            }
            .padding(.top, Spacing.xxl)
            .padding(.bottom, Spacing.l)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.canvas)
        .safeAreaInset(edge: .bottom) {
            Button(action: continueTapped) {
                if status == .testing { ProgressView().tint(Palette.onLime) } else { Text("Continue") }
            }
            .buttonStyle(.primaryLarge)
            .disabled(choice.endpoint == nil || status == .testing)
            .padding(.horizontal, Spacing.margin)
            .padding(.bottom, Spacing.s)
            .background(Palette.canvas)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: choice) {
            choice.save()
            status = .idle
            guard let endpoint = choice.endpoint else { return }
            // Wait for typing to settle, then test.
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await test(endpoint)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            AppMark(size: 56)
            Text("Where’s your team?")
                .font(Typography.largeTitle)
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Pick the TimeHuddle server to connect to. You can change it later in Settings.")
                .font(.body)
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(.horizontal, Spacing.xl)
    }

    // MARK: Rows

    private func row(_ kind: ServerKind) -> some View {
        let isSelected = choice.kind == kind
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                choice.kind = kind
                if kind == .custom, choice.customURL.isEmpty { focused = .custom }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: kind.systemImage)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isSelected ? Palette.limeText : Palette.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(isSelected ? Palette.limeSoft : Palette.fill, in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(kind.title)
                            .font(.body.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(Palette.textPrimary)
                        Text(subtitle(kind))
                            .font(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.bold))
                            .foregroundStyle(Palette.limeText)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            if isSelected {
                VStack(alignment: .leading, spacing: 10) {
                    fields(kind)
                    status.view(endpoint: choice.endpoint)
                }
                .padding(.leading, 44)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, Spacing.xl)
        .springAnimation(value: isSelected)
    }

    private func subtitle(_ kind: ServerKind) -> String {
        switch kind {
        case .development: AppConfig.developmentServer?.baseURL.host() ?? kind.subtitle
        case .production: AppConfig.productionServer?.baseURL.host() ?? kind.subtitle
        case .thisWiFi, .custom: kind.subtitle
        }
    }

    @ViewBuilder private func fields(_ kind: ServerKind) -> some View {
        switch kind {
        case .thisWiFi:
            HStack(spacing: Spacing.s) {
                LabeledField(label: "Mac’s address") {
                    TextField("192.168.1.24", text: $choice.lanHost)
                        .keyboardType(.URL)
                        .focused($focused, equals: .host)
                        .submitLabel(.next)
                        .onSubmit { focused = .port }
                }
                LabeledField(label: "Port") {
                    TextField("3100", text: $choice.lanPort)
                        .keyboardType(.numberPad)
                        .focused($focused, equals: .port)
                }
                .frame(width: 84)
            }
        case .custom:
            LabeledField(label: "Server URL") {
                TextField("https://timehuddle.example.org", text: $choice.customURL)
                    .keyboardType(.URL)
                    .focused($focused, equals: .custom)
                    .submitLabel(.go)
                    .onSubmit(continueTapped)
            }
        case .development, .production:
            EmptyView()
        }
    }

    // MARK: Actions

    private func test(_ endpoint: ServerEndpoint) async {
        status = .testing
        let outcome = await probe.check(endpoint)
        // Ignore a result for an address that has since changed.
        if choice.endpoint == endpoint { status = .done(outcome) }
    }

    private func continueTapped() {
        guard let endpoint = choice.endpoint else { return }
        focused = nil
        if case .done(.reachable) = status {
            onContinue(endpoint, choice.kind)
            return
        }
        Task {
            await test(endpoint)
            if case .done(.reachable) = status { onContinue(endpoint, choice.kind) }
        }
    }
}

/// A small caption over a monospaced text field on a raised fill.
struct LabeledField<Field: View>: View {
    let label: String
    @ViewBuilder var field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label).font(.caption).foregroundStyle(Palette.textSecondary)
            field
                .font(.body.monospaced())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, Spacing.m)
                .frame(minHeight: 44)
                .background(Palette.fill, in: RoundedRectangle(cornerRadius: Radius.control))
                .accessibilityLabel(label)
        }
    }
}

/// The result of testing the chosen server, as one colored line.
enum ConnectionStatus: Equatable {
    case idle, testing
    case done(ServerProbe.Outcome)

    @ViewBuilder func view(endpoint: ServerEndpoint?) -> some View {
        let host = endpoint.map(Self.hostAndPort) ?? ""
        switch self {
        case .idle:
            EmptyView()
        case .testing:
            line("Testing connection…", color: Palette.textSecondary, symbol: nil)
        case let .done(.reachable(ms)):
            line("Reachable · TimeHuddle server · \(ms) ms", color: Palette.done, symbol: nil)
        case .done(.notTimeHuddle):
            line("Something answered at \(host), but it isn’t a TimeHuddle server.", color: Palette.destructive, symbol: "exclamationmark.circle")
        case let .done(.unreachable(error)):
            line(error == .timeout
                 ? "\(host) didn’t answer in time. Check that the backend is running and that both devices are on the same Wi-Fi."
                 : "Can’t reach \(host). Check the address, that the backend is running, and that Local Network access is allowed.",
                 color: Palette.destructive, symbol: "exclamationmark.circle")
        }
    }

    static func hostAndPort(_ endpoint: ServerEndpoint) -> String {
        let url = endpoint.baseURL
        guard let host = url.host() else { return url.absoluteString }
        return url.port.map { "\(host):\($0)" } ?? host
    }

    private func line(_ text: String, color: Color, symbol: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            if let symbol {
                Image(systemName: symbol).accessibilityHidden(true)
            } else {
                Circle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true)
            }
            Text(text)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(color)
        .accessibilityElement(children: .combine)
    }
}

/// The open-ring mark from the app icon, on a lime tile.
struct AppMark: View {
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.745)
                .stroke(Palette.onLime, style: StrokeStyle(lineWidth: size * 0.117, lineCap: .round))
                .rotationEffect(.degrees(-60 + 90))
                .frame(width: size * 0.42, height: size * 0.42)
            Circle().fill(Palette.onLime).frame(width: size * 0.1, height: size * 0.1)
        }
        .frame(width: size, height: size)
        .background(Palette.lime, in: RoundedRectangle(cornerRadius: size / 4))
        .accessibilityHidden(true)
    }
}

#Preview("Light") { NavigationStack { ServerPickerView { _, _ in } } }
#Preview("Dark") { NavigationStack { ServerPickerView { _, _ in } }.preferredColorScheme(.dark) }
