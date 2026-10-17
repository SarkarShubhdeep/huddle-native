import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization
@testable import HuddleKit

/// A scripted transport: each call pops the next reply and records the request.
final class StubTransport: HTTPTransport {
    enum Reply: Sendable {
        case json(Int, String)
        case failure(URLError.Code)
        case hang
    }

    private let state: Mutex<(replies: [Reply], requests: [URLRequest])>

    init(_ replies: [Reply]) {
        state = Mutex((replies, []))
    }

    var requests: [URLRequest] { state.withLock { $0.requests } }
    var callCount: Int { requests.count }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let reply: Reply = state.withLock { state in
            state.requests.append(request)
            return state.replies.isEmpty ? .failure(.badServerResponse) : state.replies.removeFirst()
        }
        switch reply {
        case let .json(status, body):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            return (Data(body.utf8), response)
        case let .failure(code):
            throw URLError(code)
        case .hang:
            try await Task.sleep(for: .seconds(3600))
            throw URLError(.timedOut)
        }
    }
}

extension URLRequest {
    var bodyJSON: [String: Any]? {
        httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }
}

let testEndpoint = ServerEndpoint("192.168.1.24")!
