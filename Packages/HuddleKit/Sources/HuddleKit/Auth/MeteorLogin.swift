import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Email and password sign-in.
///
/// The backend only offers password login as the DDP `login` method, so this
/// opens a WebSocket, does `connect` → `login`, takes the resume token and closes
/// the socket. Nothing stays connected; every later call is plain REST with the
/// token as a Bearer header.
public struct MeteorLogin: Sendable {
    public typealias SocketFactory = @Sendable (URL) -> any DDPSocket

    private let makeSocket: SocketFactory
    private let timeout: Duration

    public init(
        timeout: Duration = .seconds(10),
        makeSocket: @escaping SocketFactory = { URLSessionDDPSocket(url: $0) }
    ) {
        self.timeout = timeout
        self.makeSocket = makeSocket
    }

    public func login(email: String, password: String, endpoint: ServerEndpoint) async throws -> LoginResult {
        let socket = makeSocket(Self.webSocketURL(for: endpoint))
        let payload = try Self.loginMessage(email: email, password: password)
        let timeout = self.timeout

        return try await withThrowingTaskGroup(of: LoginResult.self) { group in
            group.addTask { try await Self.exchange(on: socket, loginMessage: payload) }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw LoginError.timeout
            }
            defer {
                group.cancelAll()
                // Unblocks a receive() that is still waiting, so the group can finish.
                socket.close()
            }
            return try await group.next()!
        }
    }

    // MARK: - Protocol

    static func webSocketURL(for endpoint: ServerEndpoint) -> URL {
        var components = URLComponents(url: endpoint.baseURL, resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path += "/websocket"
        return components.url!
    }

    static func loginMessage(email: String, password: String) throws -> String {
        let message: [String: Any] = [
            "msg": "method",
            "method": "login",
            "id": "1",
            "params": [[
                "emailPassword": [
                    "email": email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                    // `raw` is always sent: migrated accounts are checked against it.
                    // An empty digest is fine; the server hashes `raw` itself.
                    "password": ["digest": sha256Hex(password), "algorithm": "sha-256", "raw": password],
                ],
            ]],
        ]
        return String(decoding: try JSONSerialization.data(withJSONObject: message, options: [.sortedKeys]), as: UTF8.self)
    }

    static let connectMessage = #"{"msg":"connect","support":["1","pre2","pre1"],"version":"1"}"#

    private static func exchange(on socket: any DDPSocket, loginMessage: String) async throws -> LoginResult {
        do {
            try await socket.send(connectMessage)
        } catch {
            throw LoginError.connectionFailed
        }

        var loginSent = false
        while true {
            let text: String
            do {
                text = try await socket.receive()
            } catch {
                try Task.checkCancellation()
                throw LoginError.connectionFailed
            }
            guard let frame = try? JSONDecoder().decode(Frame.self, from: Data(text.utf8)) else { continue }

            switch frame.msg {
            case "connected" where !loginSent:
                try await socket.send(loginMessage)
                loginSent = true
            case "failed":
                throw LoginError.server("The server doesn’t speak this protocol version.")
            case "ping":
                let pong = frame.id.map { #"{"msg":"pong","id":"\#($0)"}"# } ?? #"{"msg":"pong"}"#
                try await socket.send(pong)
            case "result" where frame.id == "1":
                if let error = frame.error { throw LoginError(error) }
                guard let result = frame.result else { throw LoginError.server("Empty login response.") }
                return result
            default:
                continue
            }
        }
    }

    static func sha256Hex(_ text: String) -> String {
        #if canImport(CryptoKit)
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        #else
        ""
        #endif
    }

    private struct Frame: Decodable {
        let msg: String?
        let id: String?
        let result: LoginResult?
        let error: MeteorErrorPayload?
    }
}

/// What a successful login returns: the user, and a resume token used as the Bearer token.
public struct LoginResult: Decodable, Equatable, Sendable {
    public let userId: String
    public let token: String
    public let expiresAt: Date?

    private enum CodingKeys: String, CodingKey { case id, token, tokenExpires }
    private struct EJSONDate: Decodable { let date: Double; enum CodingKeys: String, CodingKey { case date = "$date" } }

    public init(userId: String, token: String, expiresAt: Date?) {
        self.userId = userId
        self.token = token
        self.expiresAt = expiresAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(String.self, forKey: .id)
        token = try container.decode(String.self, forKey: .token)
        expiresAt = (try? container.decode(EJSONDate.self, forKey: .tokenExpires))
            .map { Date(timeIntervalSince1970: $0.date / 1000) }
    }
}

struct MeteorErrorPayload: Decodable {
    let error: String?
    let reason: String?

    private enum CodingKeys: String, CodingKey { case error, reason }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let text = try? container.decode(String.self, forKey: .error) {
            error = text
        } else {
            error = (try? container.decode(Int.self, forKey: .error)).map(String.init)
        }
        reason = try? container.decode(String.self, forKey: .reason)
    }
}

public enum LoginError: Error, Equatable, Sendable {
    case invalidCredentials
    /// Blocked or suspended; the server's own message.
    case suspended(String)
    /// The account must set a new password first. `token` can feed a reset flow.
    case passwordResetRequired(token: String?)
    case connectionFailed
    case timeout
    case server(String)

    init(_ payload: MeteorErrorPayload) {
        let reason = payload.reason ?? ""
        if payload.error == "PASSWORD_RESET_REQUIRED" {
            struct Detail: Decodable { let token: String? }
            let detail = try? JSONDecoder().decode(Detail.self, from: Data(reason.utf8))
            self = .passwordResetRequired(token: detail?.token)
        } else if payload.error == "403" {
            let lower = reason.lowercased()
            if lower.contains("invalid") || lower.contains("incorrect") || lower.contains("not found") {
                self = .invalidCredentials
            } else {
                self = .suspended(reason)
            }
        } else {
            self = .server(reason.isEmpty ? (payload.error ?? "Sign-in failed.") : reason)
        }
    }
}

extension LoginError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidCredentials: "That email and password don’t match. Check them and try again."
        case let .suspended(message): message.isEmpty ? "This account can’t sign in right now." : message
        case .passwordResetRequired: "This account needs a new password. Reset it in TimeHuddle on the web."
        case .connectionFailed: "Can’t reach the server."
        case .timeout: "The server took too long to answer."
        case let .server(message): message
        }
    }
}
