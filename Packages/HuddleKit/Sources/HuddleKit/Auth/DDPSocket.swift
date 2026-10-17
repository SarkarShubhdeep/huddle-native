import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A text WebSocket, just enough for the one-shot DDP login. Tests swap in a fake.
public protocol DDPSocket: Sendable {
    func send(_ text: String) async throws
    func receive() async throws -> String
    func close()
}

/// `URLSessionWebSocketTask` behind `DDPSocket`.
public final class URLSessionDDPSocket: DDPSocket, @unchecked Sendable {
    // The task is thread-safe; it isn't annotated Sendable on every platform.
    private let task: URLSessionWebSocketTask

    public init(url: URL, session: URLSession = URLSessionTransport.makeSession()) {
        task = session.webSocketTask(with: url)
        task.resume()
    }

    public func send(_ text: String) async throws {
        try await task.send(.string(text))
    }

    public func receive() async throws -> String {
        switch try await task.receive() {
        case let .string(text): return text
        case let .data(data): return String(decoding: data, as: UTF8.self)
        @unknown default: return ""
        }
    }

    public func close() {
        task.cancel(with: .normalClosure, reason: nil)
    }
}
