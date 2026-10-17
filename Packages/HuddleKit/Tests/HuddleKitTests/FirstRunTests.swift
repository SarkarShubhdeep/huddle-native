import Foundation
import Testing
@testable import HuddleKit

@Suite("ServerProbe")
struct ServerProbeTests {
    @Test("A TimeHuddle backend is reachable, with a latency")
    func reachable() async {
        let stub = StubTransport([.json(200, #"{"service":"timehuddle-meteor-backend","status":"ok"}"#)])
        let outcome = await ServerProbe(transport: stub).check(testEndpoint)
        guard case let .reachable(ms) = outcome else {
            Issue.record("Expected reachable, got \(outcome)")
            return
        }
        #expect(ms >= 1)
        #expect(stub.requests.first?.httpMethod == "GET")
        #expect(stub.requests.first?.url?.absoluteString == "http://192.168.1.24:3100")
    }

    @Test("Another web server is recognized as not TimeHuddle")
    func notTimeHuddle() async {
        let stub = StubTransport([.json(200, #"{"hello":"world"}"#)])
        #expect(await ServerProbe(transport: stub).check(testEndpoint) == .notTimeHuddle)
    }

    @Test("No route to the host is unreachable")
    func unreachable() async {
        let stub = StubTransport([.failure(.cannotConnectToHost)])
        #expect(await ServerProbe(transport: stub).check(testEndpoint) == .unreachable(.offline))
    }

    @Test("A server that never answers gives up at the cap")
    func timesOut() async {
        let stub = StubTransport([.hang])
        let clock = ContinuousClock()
        let start = clock.now
        let outcome = await ServerProbe(transport: stub, timeout: .milliseconds(100)).check(testEndpoint)
        #expect(outcome == .unreachable(.timeout))
        #expect(clock.now - start < .seconds(2))
    }
}

@Suite("TeamChoice")
struct TeamChoiceTests {
    private func teams(_ json: String) throws -> [Team] {
        try APIClient.makeDecoder().decode(TeamsList.self, from: Data(json.utf8)).teams
    }

    private let three = #"""
    {"teams":[
      {"id":"me","name":"Personal","isPersonal":true},
      {"id":"design","name":"Design Team"},
      {"id":"ops","name":"Ops"}
    ]}
    """#

    @Test("The saved team wins while you're still in it")
    func saved() throws {
        #expect(TeamChoice.restore(from: try teams(three), savedId: "ops")?.id == "ops")
    }

    @Test("Without a saved team, the first shared team beats the personal one")
    func firstShared() throws {
        #expect(TeamChoice.restore(from: try teams(three), savedId: nil)?.id == "design")
        #expect(TeamChoice.restore(from: try teams(three), savedId: "gone")?.id == "design")
    }

    @Test("Only a personal team: that one; no teams: none")
    func edges() throws {
        let personalOnly = try teams(#"{"teams":[{"id":"me","name":"Personal","isPersonal":true}]}"#)
        #expect(TeamChoice.restore(from: personalOnly, savedId: nil)?.id == "me")
        #expect(TeamChoice.restore(from: [], savedId: "me") == nil)
    }
}
