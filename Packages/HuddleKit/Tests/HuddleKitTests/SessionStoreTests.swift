import Foundation
import Testing
@testable import HuddleKit

@MainActor
@Suite("SessionStore")
struct SessionStoreTests {
    private static let okLogin = [
        #"{"msg":"connected","session":"s1"}"#,
        #"{"msg":"result","id":"1","result":{"id":"u1","token":"tok-1","tokenExpires":{"$date":4102444800000}}}"#,
    ]

    private func store(secrets: InMemorySecretStore, socket: FakeDDPSocket = FakeDDPSocket(okLogin), transport: StubTransport = StubTransport([]), now: Date = .now) -> SessionStore {
        SessionStore(secrets: secrets, login: MeteorLogin { _ in socket }, transport: transport, now: { now })
    }

    @Test("Nothing saved restores to signed out")
    func emptyRestore() {
        let sessions = store(secrets: InMemorySecretStore())
        #expect(sessions.state == .restoring)
        sessions.restore()
        #expect(sessions.state == .signedOut(nil))
    }

    @Test("Sign-in is saved and survives a relaunch")
    func persists() async throws {
        let secrets = InMemorySecretStore()
        let first = store(secrets: secrets)
        try await first.signIn(email: "a@b.c", password: "x", endpoint: testEndpoint)
        #expect(first.session?.token == "tok-1")
        #expect(first.session?.userId == "u1")

        let relaunched = store(secrets: secrets)
        relaunched.restore()
        #expect(relaunched.session == first.session)
    }

    @Test("A saved session past its expiry restores as expired")
    func expiredRestore() async throws {
        let secrets = InMemorySecretStore()
        try await store(secrets: secrets).signIn(email: "a@b.c", password: "x", endpoint: testEndpoint)

        let later = store(secrets: secrets, now: Date(timeIntervalSince1970: 4_102_444_801))
        later.restore()
        #expect(later.state == .signedOut(.expired))
        #expect(try secrets.read("session") == nil)
    }

    @Test("A failed sign-in leaves you signed out and saves nothing")
    func failedSignIn() async throws {
        let secrets = InMemorySecretStore()
        let sessions = store(secrets: secrets, socket: FakeDDPSocket([
            #"{"msg":"connected"}"#,
            #"{"msg":"result","id":"1","error":{"error":403,"reason":"Invalid email or password"}}"#,
        ]))
        sessions.restore()
        await #expect(throws: LoginError.invalidCredentials) {
            try await sessions.signIn(email: "a@b.c", password: "bad", endpoint: testEndpoint)
        }
        #expect(sessions.state == .signedOut(nil))
        #expect(try secrets.read("session") == nil)
    }

    @Test("Signing out forgets the session")
    func signOut() async throws {
        let secrets = InMemorySecretStore()
        let sessions = store(secrets: secrets)
        try await sessions.signIn(email: "a@b.c", password: "x", endpoint: testEndpoint)
        sessions.signOut()
        #expect(sessions.state == .signedOut(.userRequested))
        #expect(try secrets.read("session") == nil)
    }

    @Test("A 401 from any call signs out with .expired")
    func unauthorizedSignsOut() async throws {
        let transport = StubTransport([.json(401, "{}")])
        let sessions = store(secrets: InMemorySecretStore(), transport: transport)
        try await sessions.signIn(email: "a@b.c", password: "x", endpoint: testEndpoint)

        let client = try #require(sessions.makeClient())
        await #expect(throws: APIError.unauthorized) {
            let _: Bool = try await client.query("teams.list")
        }
        #expect(sessions.state == .signedOut(.expired))
        #expect(transport.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer tok-1")
    }
}
