import Foundation
import Observation

/// A signed-in user on one server.
public struct Session: Codable, Equatable, Sendable {
    public let endpoint: ServerEndpoint
    public let userId: String
    public let token: String
    public let expiresAt: Date?

    public init(endpoint: ServerEndpoint, userId: String, token: String, expiresAt: Date?) {
        self.endpoint = endpoint
        self.userId = userId
        self.token = token
        self.expiresAt = expiresAt
    }

    public func isExpired(at now: Date = .now) -> Bool {
        expiresAt.map { $0 <= now } ?? false
    }
}

/// Owns sign-in state. The session lives in a `SecretStore` (the Keychain on iOS),
/// survives relaunches for the token's 30-day life, and is dropped the moment
/// the backend says the token is no good.
@MainActor
@Observable
public final class SessionStore {
    public enum SignOutReason: Equatable, Sendable {
        case userRequested
        case expired
    }

    public enum State: Equatable, Sendable {
        case restoring
        case signedOut(SignOutReason?)
        case signedIn(Session)
    }

    public private(set) var state: State = .restoring

    public var session: Session? {
        if case let .signedIn(session) = state { return session }
        return nil
    }

    @ObservationIgnored private let secrets: any SecretStore
    @ObservationIgnored private let loginService: MeteorLogin
    @ObservationIgnored private let transport: any HTTPTransport
    @ObservationIgnored private let now: @Sendable () -> Date

    private static let key = "session"

    public init(
        secrets: any SecretStore,
        login: MeteorLogin = MeteorLogin(),
        transport: any HTTPTransport = URLSessionTransport(),
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.secrets = secrets
        self.loginService = login
        self.transport = transport
        self.now = now
    }

    /// Loads a saved session, if there is one that hasn't expired.
    public func restore() {
        guard let data = try? secrets.read(Self.key),
              let saved = try? JSONDecoder().decode(Session.self, from: data)
        else {
            state = .signedOut(nil)
            return
        }
        if saved.isExpired(at: now()) {
            forget()
            state = .signedOut(.expired)
        } else {
            state = .signedIn(saved)
        }
    }

    public func signIn(email: String, password: String, endpoint: ServerEndpoint) async throws {
        let result = try await loginService.login(email: email, password: password, endpoint: endpoint)
        let session = Session(endpoint: endpoint, userId: result.userId, token: result.token, expiresAt: result.expiresAt)
        try secrets.write(JSONEncoder().encode(session), for: Self.key)
        state = .signedIn(session)
    }

    /// Drops the session on this device. (The token stays valid on the server
    /// until it expires; there is no REST logout to call.)
    public func signOut(_ reason: SignOutReason = .userRequested) {
        forget()
        state = .signedOut(reason)
    }

    /// An API client bound to the current session. A 401 from any call signs out,
    /// unless a newer sign-in already replaced that token.
    public func makeClient() -> APIClient? {
        guard let session else { return nil }
        let token = session.token
        return APIClient(
            endpoint: session.endpoint,
            transport: transport,
            token: { token },
            onUnauthorized: { [weak self] in
                await self?.tokenRejected(token)
            }
        )
    }

    private func tokenRejected(_ token: String) {
        guard session?.token == token else { return }
        signOut(.expired)
    }

    private func forget() {
        try? secrets.delete(Self.key)
    }
}
