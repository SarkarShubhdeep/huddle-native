import Foundation

/// The TimeHuddle Meteor backend this app talks to.
///
/// Accepts what a person would type into the server picker — `192.168.1.24`,
/// `192.168.1.24:3100`, `http://192.168.1.24:3100/`, `timecore-dev.example.org` —
/// and normalizes it to a base URL with no trailing slash.
public struct ServerEndpoint: Hashable, Sendable, Codable {
    /// The port the Meteor backend listens on in local development.
    public static let defaultLocalPort = 3100

    public let baseURL: URL

    public init?(_ input: String) {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if !text.contains("://") {
            // A bare LAN address means the local dev stack: plain http on the backend port.
            // Anything else is assumed to be a real host behind TLS.
            text = Self.isLocalHost(text) ? "http://\(text)" : "https://\(text)"
        }
        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty
        else { return nil }

        if components.port == nil, scheme == "http", Self.isLocalHost(host) {
            components.port = Self.defaultLocalPort
        }
        components.scheme = scheme
        components.path = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.query = nil
        components.fragment = nil

        guard let url = components.url else { return nil }
        baseURL = url
    }

    /// True for addresses that only resolve on the local network: RFC 1918 IPv4
    /// ranges, link-local, loopback and `.local` mDNS names.
    public var isLocalNetwork: Bool {
        baseURL.host.map(Self.isLocalHost) ?? false
    }

    static func isLocalHost(_ hostOrHostPort: String) -> Bool {
        let host = hostOrHostPort.split(separator: ":").first.map(String.init)?.lowercased() ?? ""
        if host == "localhost" || host.hasSuffix(".local") { return true }
        let octets = host.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else { return false }
        switch (octets[0], octets[1]) {
        case (10, _), (127, _), (192, 168), (169, 254): return true
        case (172, 16...31): return true
        default: return false
        }
    }
}
