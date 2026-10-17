import Foundation
import HuddleKit

/// The servers the picker offers. Development and Production come from build
/// settings and are hidden when not configured.
enum ServerKind: String, CaseIterable, Identifiable, Sendable {
    case thisWiFi, development, production, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .thisWiFi: "This Wi-Fi"
        case .development: "Development"
        case .production: "Production"
        case .custom: "Custom URL"
        }
    }

    var subtitle: String {
        switch self {
        case .thisWiFi: "A TimeHuddle server on your Mac"
        case .development: "Shared test server"
        case .production: "Live team data"
        case .custom: "Any TimeHuddle server"
        }
    }

    var systemImage: String {
        switch self {
        case .thisWiFi: "wifi"
        case .development: "server.rack"
        case .production: "globe"
        case .custom: "link"
        }
    }
}

/// Build-time configuration read from Info.plist.
enum AppConfig {
    static var defaultServer: ServerEndpoint? { endpoint(for: "HNDefaultServerURL") }
    static var developmentServer: ServerEndpoint? { endpoint(for: "HNDevServerURL") }
    static var productionServer: ServerEndpoint? { endpoint(for: "HNProdServerURL") }

    static var availableKinds: [ServerKind] {
        ServerKind.allCases.filter { kind in
            switch kind {
            case .development: developmentServer != nil
            case .production: productionServer != nil
            case .thisWiFi, .custom: true
            }
        }
    }

    private static func endpoint(for key: String) -> ServerEndpoint? {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String).flatMap(ServerEndpoint.init)
    }
}

/// What the picker last held, so it opens where you left it.
struct ServerChoice: Equatable {
    var kind: ServerKind
    /// "192.168.1.24" for This Wi-Fi.
    var lanHost: String
    var lanPort: String
    var customURL: String

    /// The endpoint for the current choice, or nil while the fields don't make one.
    var endpoint: ServerEndpoint? {
        switch kind {
        case .thisWiFi:
            let host = lanHost.trimmingCharacters(in: .whitespaces)
            let port = lanPort.trimmingCharacters(in: .whitespaces)
            guard !host.isEmpty else { return nil }
            return ServerEndpoint(port.isEmpty ? host : "http://\(host):\(port)")
        case .development: return AppConfig.developmentServer
        case .production: return AppConfig.productionServer
        case .custom: return ServerEndpoint(customURL)
        }
    }

    // MARK: Persistence

    private enum Key {
        static let kind = "server.kind", host = "server.lanHost", port = "server.lanPort", custom = "server.customURL"
    }

    static func load(_ defaults: UserDefaults = .standard) -> ServerChoice {
        let fallback = AppConfig.defaultServer?.baseURL
        let kind = defaults.string(forKey: Key.kind).flatMap(ServerKind.init(rawValue:))
            .flatMap { AppConfig.availableKinds.contains($0) ? $0 : nil } ?? .thisWiFi
        return ServerChoice(
            kind: kind,
            lanHost: defaults.string(forKey: Key.host) ?? fallback?.host() ?? "",
            lanPort: defaults.string(forKey: Key.port) ?? fallback?.port.map(String.init) ?? String(ServerEndpoint.defaultLocalPort),
            customURL: defaults.string(forKey: Key.custom) ?? ""
        )
    }

    func save(_ defaults: UserDefaults = .standard) {
        defaults.set(kind.rawValue, forKey: Key.kind)
        defaults.set(lanHost, forKey: Key.host)
        defaults.set(lanPort, forKey: Key.port)
        defaults.set(customURL, forKey: Key.custom)
    }
}
