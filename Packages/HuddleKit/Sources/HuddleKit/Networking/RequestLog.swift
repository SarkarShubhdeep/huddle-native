import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization

/// The most recent requests and how they went, for Settings › Diagnostics.
public final class RequestLog: Sendable {
    public struct Entry: Sendable, Equatable, Identifiable {
        public let id: Int
        /// `clock.start`, or `GET /` for the server check.
        public let name: String
        public let startedAt: Date
        public let milliseconds: Int
        /// The HTTP status, or nil when no response came back.
        public let status: Int?
        /// Why it failed without a response (offline, timed out, cancelled).
        public let failure: String?

        public var succeeded: Bool { status.map { (200..<300).contains($0) } ?? false }
    }

    private struct State {
        var entries: [Entry] = []
        var next = 0
    }

    private let state = Mutex(State())
    private let capacity: Int

    public init(capacity: Int = 50) {
        self.capacity = capacity
    }

    /// Newest first.
    public var entries: [Entry] { state.withLock { $0.entries.reversed() } }

    public func record(name: String, startedAt: Date, milliseconds: Int, status: Int?, failure: String?) {
        state.withLock { state in
            state.entries.append(Entry(id: state.next, name: name, startedAt: startedAt,
                                       milliseconds: milliseconds, status: status, failure: failure))
            state.next += 1
            if state.entries.count > capacity { state.entries.removeFirst(state.entries.count - capacity) }
        }
    }

    public func clear() { state.withLock { $0.entries.removeAll() } }

    /// `POST /api/clock_start` → `clock.start`; anything else → `GET /path`.
    static func name(for request: URLRequest) -> String {
        let path = request.url?.path ?? ""
        if path.hasPrefix("/api/") {
            return path.dropFirst(5).replacingOccurrences(of: "_", with: ".")
        }
        return "\(request.httpMethod ?? "GET") \(path.isEmpty ? "/" : path)"
    }
}

/// Wraps a transport and records every request it sends in a `RequestLog`.
public struct LoggingTransport: HTTPTransport {
    private let base: any HTTPTransport
    private let log: RequestLog
    private let clock = ContinuousClock()

    public init(_ base: any HTTPTransport, log: RequestLog) {
        self.base = base
        self.log = log
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let startedAt = Date()
        let start = clock.now
        do {
            let result = try await base.send(request)
            log.record(name: RequestLog.name(for: request), startedAt: startedAt,
                       milliseconds: milliseconds(since: start), status: result.1.statusCode, failure: nil)
            return result
        } catch {
            log.record(name: RequestLog.name(for: request), startedAt: startedAt,
                       milliseconds: milliseconds(since: start), status: nil,
                       failure: APIError.from(error).localizedDescription)
            throw error
        }
    }

    private func milliseconds(since start: ContinuousClock.Instant) -> Int {
        let elapsed = clock.now - start
        return Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
    }
}
