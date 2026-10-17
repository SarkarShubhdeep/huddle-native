import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Everything a backend call can fail with, in terms the UI can act on.
public enum APIError: Error, Equatable, Sendable {
    /// The token is missing, invalid or expired. The session signs out.
    case unauthorized
    /// The backend rejected the call: `{ error, reason }` from a Meteor method,
    /// e.g. `plan-required`, `no-active-shift`, `forbidden`.
    case server(code: String, reason: String, status: Int)
    /// No route to the server: Wi-Fi off, wrong address, backend not running.
    case offline
    /// The connection dropped mid-request. Typical right after the app resumes
    /// from the background, when iOS hands back a dead keep-alive socket.
    case connectionLost
    /// No response within the request timeout.
    case timeout
    case cancelled
    case decoding(String)
    case invalidResponse

    /// Worth one automatic retry for a read.
    public var isTransient: Bool {
        self == .connectionLost || self == .timeout
    }

    /// The backend's error code, when the server sent one.
    public var serverCode: String? {
        if case let .server(code, _, _) = self { return code }
        return nil
    }

    public static func from(_ error: any Error) -> APIError {
        if let apiError = error as? APIError { return apiError }
        if error is CancellationError { return .cancelled }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled: return .cancelled
            case .timedOut: return .timeout
            case .networkConnectionLost: return .connectionLost
            case .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost,
                 .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff,
                 .secureConnectionFailed, .appTransportSecurityRequiresSecureConnection:
                return .offline
            case .userAuthenticationRequired: return .unauthorized
            default: return .offline
            }
        }
        if error is DecodingError { return .decoding(String(describing: error)) }
        return .offline
    }
}

extension APIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unauthorized: "Your session expired. Sign in again."
        case let .server(_, reason, _): reason.isEmpty ? "The server couldn’t do that." : reason
        case .offline: "Can’t reach the server."
        case .connectionLost: "The connection dropped."
        case .timeout: "The server took too long to answer."
        case .cancelled: "Cancelled."
        case .decoding: "The server sent something unexpected."
        case .invalidResponse: "The server sent something unexpected."
        }
    }
}
