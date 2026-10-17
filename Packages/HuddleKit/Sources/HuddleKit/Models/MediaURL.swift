import Foundation

/// Media URLs are stored with whatever host served the backend at upload time,
/// which goes stale the moment that host changes (every new DHCP lease on a dev
/// Mac). Anything under the backend's own media paths is re-based onto the
/// server this session talks to; links to anywhere else are left alone.
/// Same rule as the web app's `resolveMediaUrl`.
public enum MediaURL {
    static let backendPrefixes = ["/uploads/", "/pulsevault/"]

    public static func resolve(_ raw: String?, against endpoint: ServerEndpoint) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }

        if raw.hasPrefix("/") {
            guard isBackendPath(raw) else { return URL(string: raw, relativeTo: endpoint.baseURL)?.absoluteURL }
            return URL(string: endpoint.baseURL.absoluteString + raw)
        }

        guard var components = URLComponents(string: raw), components.host != nil else {
            return URL(string: raw)
        }
        guard isBackendPath(components.path),
              let base = URLComponents(url: endpoint.baseURL, resolvingAgainstBaseURL: false)
        else { return components.url }

        components.scheme = base.scheme
        components.host = base.host
        components.port = base.port
        components.path = base.path + components.path
        return components.url
    }

    /// Re-bases image and link targets inside post markdown, e.g.
    /// `![](http://10.0.0.9:3100/uploads/media/a.png)` → the current server.
    public static func rebaseMarkdown(_ text: String, against endpoint: ServerEndpoint) -> String {
        let pattern = #"\]\((https?://[^/\s)]+)?(/(?:uploads|pulsevault)/[^\s)]*)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let base = NSRegularExpression.escapedTemplate(for: endpoint.baseURL.absoluteString)
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "](\(base)$2)")
    }

    private static func isBackendPath(_ path: String) -> Bool {
        backendPrefixes.contains { path.hasPrefix($0) }
    }
}
