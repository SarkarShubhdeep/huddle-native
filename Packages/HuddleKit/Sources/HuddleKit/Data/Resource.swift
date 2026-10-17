import Foundation
import Observation
import Synchronization

/// One screen's worth of server data, and the refresh rules that keep
/// pull-to-refresh from ever hanging:
///
/// - **Stale data stays.** `value` is never cleared by a refresh; a failed
///   refresh sets `error` and keeps what you had.
/// - **Single-flight.** A second refresh while one is running joins it.
/// - **The fetch outlives the caller.** It runs in its own task, so SwiftUI
///   cancelling `.refreshable` (or a view going away) can't kill it halfway.
/// - **The caller waits at most `maxWait`** (6 s by default). The spinner stops
///   then, even on a dead network; if the data arrives later, it still lands.
@MainActor
@Observable
public final class Resource<Value: Codable & Sendable> {
    public private(set) var value: Value?
    public private(set) var error: APIError?
    public private(set) var isLoading = false
    public private(set) var lastUpdated: Date?

    @ObservationIgnored private let fetch: @Sendable () async throws -> Value
    @ObservationIgnored private let store: (any SnapshotStore)?
    @ObservationIgnored private let cacheKey: String?
    @ObservationIgnored private var inFlight: Task<Void, Never>?

    public init(
        cacheKey: String? = nil,
        store: (any SnapshotStore)? = nil,
        fetch: @escaping @Sendable () async throws -> Value
    ) {
        self.cacheKey = cacheKey
        self.store = store
        self.fetch = fetch
    }

    /// First appearance: show the cached copy right away, then refresh.
    public func load(maxWait: Duration = .seconds(6)) async {
        if value == nil, let cacheKey, let snapshot = store?.load(Value.self, key: cacheKey) {
            value = snapshot.value
            lastUpdated = snapshot.savedAt
        }
        await refresh(maxWait: maxWait)
    }

    /// Fetches fresh data. Returns when it lands or after `maxWait`, whichever is first.
    public func refresh(maxWait: Duration = .seconds(6)) async {
        let task = inFlight ?? start()
        await Self.wait(for: task, atMost: maxWait)
    }

    /// Sets the value locally — an optimistic update after an action, before the
    /// confirming refetch.
    public func set(_ newValue: Value) {
        value = newValue
        error = nil
        save(newValue)
    }

    /// True while a fetch is running, even after the caller stopped waiting.
    public var isRefreshing: Bool { inFlight != nil }

    // MARK: - Internals

    private func start() -> Task<Void, Never> {
        let fetch = self.fetch
        let task = Task { [weak self] in
            self?.isLoading = true
            let result: Result<Value, any Error>
            do {
                result = .success(try await fetch())
            } catch {
                result = .failure(error)
            }
            self?.finish(result)
        }
        inFlight = task
        return task
    }

    private func finish(_ result: Result<Value, any Error>) {
        switch result {
        case let .success(fresh):
            value = fresh
            error = nil
            lastUpdated = .now
            save(fresh)
        case let .failure(failure):
            error = APIError.from(failure)
        }
        isLoading = false
        inFlight = nil
    }

    private func save(_ value: Value) {
        if let cacheKey { store?.save(value, key: cacheKey) }
    }

    /// Waits for `task`, but never longer than `limit`, and returns at once if the
    /// caller is cancelled. `task` itself is never cancelled here.
    private static func wait(for task: Task<Void, Never>, atMost limit: Duration) async {
        let gate = Gate()
        let timer = Task {
            try? await Task.sleep(for: limit)
            gate.open()
        }
        let watcher = Task {
            await task.value
            gate.open()
        }
        await withTaskCancellationHandler {
            await gate.wait()
        } onCancel: {
            gate.open()
        }
        timer.cancel()
        watcher.cancel()
    }
}

/// A one-shot latch: `wait()` returns once `open()` has been called, from anywhere, any number of times.
private final class Gate: Sendable {
    private struct State {
        var isOpen = false
        var waiter: CheckedContinuation<Void, Never>?
    }

    private let state = Mutex(State())

    func wait() async {
        await withCheckedContinuation { continuation in
            let resumeNow = state.withLock { state in
                if state.isOpen { return true }
                state.waiter = continuation
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    func open() {
        let waiter = state.withLock { state -> CheckedContinuation<Void, Never>? in
            state.isOpen = true
            defer { state.waiter = nil }
            return state.waiter
        }
        waiter?.resume()
    }
}
