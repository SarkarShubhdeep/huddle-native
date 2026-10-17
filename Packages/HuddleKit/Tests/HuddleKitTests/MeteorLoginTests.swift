import Foundation
import Testing
@testable import HuddleKit

@Suite("MeteorLogin")
struct MeteorLoginTests {
    private func login(_ socket: FakeDDPSocket, timeout: Duration = .seconds(2)) -> MeteorLogin {
        MeteorLogin(timeout: timeout) { _ in socket }
    }

    private static let connected = [#"{"server_id":"0"}"#, #"{"msg":"connected","session":"s1"}"#]

    @Test("connect → login → resume token, answering pings and ignoring other frames")
    func happyPath() async throws {
        let socket = FakeDDPSocket(Self.connected + [
            #"{"msg":"ping","id":"p1"}"#,
            #"{"msg":"added","collection":"users","id":"u1","fields":{}}"#,
            #"{"msg":"result","id":"1","result":{"id":"u1","token":"resume-abc","tokenExpires":{"$date":1763000000000},"type":"password"}}"#,
        ])
        let result = try await login(socket).login(email: "  You@Company.com ", password: "hunter2", endpoint: testEndpoint)

        #expect(result == LoginResult(userId: "u1", token: "resume-abc", expiresAt: Date(timeIntervalSince1970: 1_763_000_000)))
        #expect(socket.closed)

        let sent = socket.sent
        #expect(sent.first == MeteorLogin.connectMessage)
        #expect(sent.contains(#"{"msg":"pong","id":"p1"}"#))

        let loginFrame = try #require(sent.first { $0.contains(#""method":"login""#) })
        let json = try #require(try JSONSerialization.jsonObject(with: Data(loginFrame.utf8)) as? [String: Any])
        let params = try #require((json["params"] as? [[String: Any]])?.first?["emailPassword"] as? [String: Any])
        #expect(params["email"] as? String == "you@company.com")
        let password = try #require(params["password"] as? [String: Any])
        #expect(password["raw"] as? String == "hunter2")
        #expect(password["algorithm"] as? String == "sha-256")
    }

    @Test("Login is only sent after the server says connected")
    func waitsForConnected() async throws {
        let socket = FakeDDPSocket([#"{"server_id":"0"}"#])
        await #expect(throws: LoginError.connectionFailed) {
            _ = try await login(socket).login(email: "a@b.c", password: "x", endpoint: testEndpoint)
        }
        #expect(socket.sent == [MeteorLogin.connectMessage])
    }

    @Test("A wrong password is .invalidCredentials")
    func wrongPassword() async throws {
        let socket = FakeDDPSocket(Self.connected + [
            #"{"msg":"result","id":"1","error":{"isClientSafe":true,"error":403,"reason":"Invalid email or password","message":"Invalid email or password [403]","errorType":"Meteor.Error"}}"#,
        ])
        await #expect(throws: LoginError.invalidCredentials) {
            _ = try await login(socket).login(email: "a@b.c", password: "nope", endpoint: testEndpoint)
        }
    }

    @Test("A blocked account carries the server's message")
    func suspended() async throws {
        let socket = FakeDDPSocket(Self.connected + [
            #"{"msg":"result","id":"1","error":{"error":403,"reason":"Account suspended"}}"#,
        ])
        await #expect(throws: LoginError.suspended("Account suspended")) {
            _ = try await login(socket).login(email: "a@b.c", password: "x", endpoint: testEndpoint)
        }
    }

    @Test("PASSWORD_RESET_REQUIRED surfaces its reset token")
    func resetRequired() async throws {
        let socket = FakeDDPSocket(Self.connected + [
            #"{"msg":"result","id":"1","error":{"error":"PASSWORD_RESET_REQUIRED","reason":"{\"message\":\"Set a new password\",\"token\":\"rst-1\"}"}}"#,
        ])
        await #expect(throws: LoginError.passwordResetRequired(token: "rst-1")) {
            _ = try await login(socket).login(email: "a@b.c", password: "x", endpoint: testEndpoint)
        }
    }

    @Test("A server that never answers hits the time cap and the socket is closed")
    func timesOut() async throws {
        let socket = FakeDDPSocket(Self.connected, hangAtEnd: true)
        let start = ContinuousClock.now
        await #expect(throws: LoginError.timeout) {
            _ = try await login(socket, timeout: .milliseconds(200)).login(email: "a@b.c", password: "x", endpoint: testEndpoint)
        }
        #expect(ContinuousClock.now - start < .seconds(2))
        #expect(socket.closed)
    }

    @Test("The WebSocket URL follows the endpoint's scheme", arguments: [
        ("192.168.1.24", "ws://192.168.1.24:3100/websocket"),
        ("timecore-dev.example.org", "wss://timecore-dev.example.org/websocket"),
    ])
    func webSocketURL(input: String, expected: String) throws {
        let endpoint = try #require(ServerEndpoint(input))
        #expect(MeteorLogin.webSocketURL(for: endpoint).absoluteString == expected)
    }

    #if canImport(CryptoKit)
    @Test("The password digest is lowercase hex SHA-256, as Meteor expects")
    func digest() {
        #expect(MeteorLogin.sha256Hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
    #endif
}
