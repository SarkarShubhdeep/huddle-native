import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization
import Testing
@testable import HuddleKit

@Suite("APIClient")
struct APIClientTests {
    private func client(_ transport: StubTransport, token: String? = "tok", onUnauthorized: @escaping @Sendable () async -> Void = {}) -> APIClient {
        APIClient(endpoint: testEndpoint, transport: transport, retryDelay: .zero, token: { token }, onUnauthorized: onUnauthorized)
    }

    private struct TeamParams: Encodable, Sendable { let teamId: String }
    private struct Item: Decodable, Equatable { let id: String }

    @Test("POSTs to /api/<method_with_underscores> with JSON body and Bearer token")
    func buildsRequest() async throws {
        let stub = StubTransport([.json(200, #"{"result":{"id":"a"}}"#)])
        let item: Item = try await client(stub).query("clock.activeForUser", TeamParams(teamId: "t1"))
        #expect(item == Item(id: "a"))

        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "http://192.168.1.24:3100/api/clock_activeForUser")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.bodyJSON?["teamId"] as? String == "t1")
    }

    @Test("No token, no Authorization header; no params sends {}")
    func anonymous() async throws {
        let stub = StubTransport([.json(200, #"{"result":true}"#)])
        let ok: Bool = try await client(stub, token: nil).query("teams.list")
        #expect(ok)
        #expect(stub.requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(stub.requests.first?.httpBody == Data("{}".utf8))
    }

    @Test("A null or missing result decodes as nil for an optional", arguments: [#"{"result":null}"#, "{}"])
    func nullResult(body: String) async throws {
        let stub = StubTransport([.json(200, body)])
        let item: Item? = try await client(stub).query("clock.activeForUser")
        #expect(item == nil)
    }

    @Test("A null result for a non-optional is a decoding error")
    func nullForRequired() async throws {
        let stub = StubTransport([.json(200, #"{"result":null}"#)])
        await #expect(throws: APIError.self) {
            let _: Item = try await client(stub).query("tickets.get")
        }
    }

    @Test("{error, reason} becomes .server with the code")
    func serverError() async throws {
        let stub = StubTransport([.json(400, #"{"error":"plan-required","reason":"Add a wrap-up before clocking out"}"#)])
        do {
            let _: Item = try await client(stub).mutate("clock.stop")
            Issue.record("expected an error")
        } catch let error as APIError {
            #expect(error == .server(code: "plan-required", reason: "Add a wrap-up before clocking out", status: 400))
            #expect(error.serverCode == "plan-required")
        }
    }

    @Test("A numeric Meteor error code is kept as a string")
    func numericCode() async throws {
        let stub = StubTransport([.json(403, #"{"error":403,"reason":"Nope"}"#)])
        await #expect(throws: APIError.server(code: "403", reason: "Nope", status: 403)) {
            let _: Bool = try await client(stub).query("x.y")
        }
    }

    @Test("401 and not-authorized become .unauthorized and fire the callback", arguments: [
        StubTransport.Reply.json(401, "{}"),
        StubTransport.Reply.json(400, #"{"error":"not-authorized","reason":"Invalid or expired token"}"#),
    ])
    func unauthorized(reply: StubTransport.Reply) async throws {
        let fired = Mutex(false)
        let stub = StubTransport([reply])
        await #expect(throws: APIError.unauthorized) {
            let _: Bool = try await client(stub, onUnauthorized: { fired.withLock { $0 = true } }).query("teams.list")
        }
        #expect(fired.withLock { $0 })
    }

    @Test("A read retries once after a dropped connection")
    func queryRetries() async throws {
        let stub = StubTransport([.failure(.networkConnectionLost), .json(200, #"{"result":true}"#)])
        let ok: Bool = try await client(stub).query("teams.list")
        #expect(ok)
        #expect(stub.callCount == 2)
    }

    @Test("A read gives up after the second failure")
    func queryGivesUp() async throws {
        let stub = StubTransport([.failure(.timedOut), .failure(.timedOut), .json(200, #"{"result":true}"#)])
        await #expect(throws: APIError.timeout) {
            let _: Bool = try await client(stub).query("teams.list")
        }
        #expect(stub.callCount == 2)
    }

    @Test("A write never retries")
    func mutateDoesNotRetry() async throws {
        let stub = StubTransport([.failure(.networkConnectionLost), .json(200, #"{"result":true}"#)])
        await #expect(throws: APIError.connectionLost) {
            let _: Bool = try await client(stub).mutate("clock.start")
        }
        #expect(stub.callCount == 1)
    }

    @Test("An unreachable host is .offline and not retried")
    func offline() async throws {
        let stub = StubTransport([.failure(.cannotConnectToHost)])
        await #expect(throws: APIError.offline) {
            let _: Bool = try await client(stub).query("teams.list")
        }
        #expect(stub.callCount == 1)
    }

    @Test("Dates decode from epoch ms and ISO strings")
    func dates() async throws {
        struct Stamped: Decodable { let a: Date; let b: Date; let c: Date }
        let stub = StubTransport([.json(200, #"{"result":{"a":1760000000000,"b":"2026-07-22T14:03:11.123Z","c":"2026-07-22T14:03:11Z"}}"#)])
        let value: Stamped = try await client(stub).query("x")
        #expect(value.a == Date(timeIntervalSince1970: 1_760_000_000))
        #expect(abs(value.b.timeIntervalSince(value.c) - 0.123) < 0.001)
    }

    @Test("ping recognises the TimeHuddle backend")
    func ping() async throws {
        let ok = StubTransport([.json(200, #"{"service":"timehuddle-meteor-backend","status":"ok"}"#)])
        #expect(try await client(ok).ping())
        #expect(ok.requests.first?.httpMethod == "GET")

        let other = StubTransport([.json(200, #"{"hello":"world"}"#)])
        #expect(try await client(other).ping() == false)
    }
}
