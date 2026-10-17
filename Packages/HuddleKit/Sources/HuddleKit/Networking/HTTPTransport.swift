import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Sends one HTTP request. `APIClient` talks to the network only through this,
/// so tests can swap in a stub.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// The real transport. Every request is bounded: 10 s without a byte, 20 s
/// in total, and it fails fast instead of waiting for connectivity — the
/// opposite of what made the Capacitor app's refresh hang.
public final class URLSessionTransport: HTTPTransport, @unchecked Sendable {
    // URLSession is thread-safe; it isn't annotated Sendable on every platform.
    private let session: URLSession

    public init(session: URLSession = URLSessionTransport.makeSession()) {
        self.session = session
    }

    public static func makeSession(
        requestTimeout: TimeInterval = 10,
        resourceTimeout: TimeInterval = 20
    ) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = resourceTimeout
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpShouldSetCookies = false
        #if !os(Linux)
        config.waitsForConnectivity = false
        #endif
        return URLSession(configuration: config)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        return (data, http)
    }
}
