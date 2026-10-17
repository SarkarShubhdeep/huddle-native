import Foundation
import Synchronization
@testable import HuddleKit

/// Plays back scripted server frames in order and records what the client sent.
/// With `hangAtEnd`, `receive()` blocks once the script runs out, until `close()`.
final class FakeDDPSocket: DDPSocket {
    private struct State {
        var script: [String]
        var sent: [String] = []
        var closed = false
    }

    private let state: Mutex<State>
    private let hangAtEnd: Bool

    init(_ script: [String], hangAtEnd: Bool = false) {
        state = Mutex(State(script: script))
        self.hangAtEnd = hangAtEnd
    }

    var sent: [String] { state.withLock { $0.sent } }
    var closed: Bool { state.withLock { $0.closed } }

    func send(_ text: String) async throws {
        state.withLock { $0.sent.append(text) }
    }

    func receive() async throws -> String {
        while true {
            let next: String?? = state.withLock { state in
                if state.closed { return .some(nil) }
                if !state.script.isEmpty { return .some(state.script.removeFirst()) }
                return nil
            }
            switch next {
            case let .some(.some(frame)): return frame
            case .some(.none): throw URLError(.cancelled)
            case .none:
                guard hangAtEnd else { throw URLError(.networkConnectionLost) }
                try await Task.sleep(for: .milliseconds(5))
            }
        }
    }

    func close() {
        state.withLock { $0.closed = true }
    }
}
