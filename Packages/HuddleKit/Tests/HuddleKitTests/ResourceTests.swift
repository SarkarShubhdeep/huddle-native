import Foundation
import Synchronization
import Testing
@testable import HuddleKit

/// A fetch the test controls: counts calls, and each call waits for `release()`
/// (or returns at once when not gated).
private final class ControlledFetch: Sendable {
    private struct State {
        var calls = 0
        var gated: Bool
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    private let state: Mutex<State>
    private let results: Mutex<[Result<[String], APIError>]>

    init(gated: Bool, results: [Result<[String], APIError>]) {
        state = Mutex(State(gated: gated))
        self.results = Mutex(results)
    }

    var calls: Int { state.withLock { $0.calls } }

    func callAsFunction() async throws -> [String] {
        let mustWait = state.withLock { state -> Bool in
            state.calls += 1
            return state.gated
        }
        if mustWait {
            await withCheckedContinuation { continuation in
                let releaseNow = state.withLock { state -> Bool in
                    guard state.gated else { return true }
                    state.waiters.append(continuation)
                    return false
                }
                if releaseNow { continuation.resume() }
            }
        }
        let next = results.withLock { $0.isEmpty ? .success(["fallback"]) : $0.removeFirst() }
        return try next.get()
    }

    func release() {
        let waiters = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.gated = false
            defer { state.waiters = [] }
            return state.waiters
        }
        waiters.forEach { $0.resume() }
    }
}

@MainActor
@Suite("Resource")
struct ResourceTests {
    private func eventually(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test("A refresh stores the value and its time")
    func basic() async {
        let fetch = ControlledFetch(gated: false, results: [.success(["a"])])
        let resource = Resource { try await fetch() }
        await resource.refresh()
        #expect(resource.value == ["a"])
        #expect(resource.error == nil)
        #expect(resource.lastUpdated != nil)
        #expect(!resource.isLoading)
    }

    @Test("Concurrent refreshes share one fetch")
    func singleFlight() async {
        let fetch = ControlledFetch(gated: true, results: [.success(["a"])])
        let resource = Resource { try await fetch() }

        async let first: Void = resource.refresh()
        async let second: Void = resource.refresh()
        await eventually { fetch.calls == 1 && resource.isLoading }
        fetch.release()
        _ = await (first, second)

        #expect(fetch.calls == 1)
        #expect(resource.value == ["a"])
    }

    @Test("A slow fetch releases the caller at the cap, and still lands later")
    func cap() async {
        let fetch = ControlledFetch(gated: true, results: [.success(["late"])])
        let resource = Resource { try await fetch() }

        let start = ContinuousClock.now
        await resource.refresh(maxWait: .milliseconds(150))
        let waited = ContinuousClock.now - start

        #expect(waited >= .milliseconds(140))
        #expect(waited < .seconds(2))
        #expect(resource.value == nil)
        #expect(resource.isRefreshing)

        fetch.release()
        await eventually { resource.value != nil }
        #expect(resource.value == ["late"])
        #expect(!resource.isRefreshing)
    }

    @Test("A failed refresh keeps the old value and reports the error")
    func keepsStaleData() async {
        let fetch = ControlledFetch(gated: false, results: [.success(["good"]), .failure(.offline)])
        let resource = Resource { try await fetch() }
        await resource.refresh()
        await resource.refresh()
        #expect(resource.value == ["good"])
        #expect(resource.error == .offline)
    }

    @Test("Cancelling the caller (pull-to-refresh going away) doesn't cancel the fetch")
    func callerCancellation() async {
        let fetch = ControlledFetch(gated: true, results: [.success(["kept"])])
        let resource = Resource { try await fetch() }

        let caller = Task { await resource.refresh(maxWait: .seconds(30)) }
        await eventually { fetch.calls == 1 }
        caller.cancel()
        let start = ContinuousClock.now
        await caller.value
        #expect(ContinuousClock.now - start < .seconds(1))

        fetch.release()
        await eventually { resource.value != nil }
        #expect(resource.value == ["kept"])
    }

    @Test("load() shows the cached copy first, then the fresh one, and caches it")
    func cacheFirst() async {
        let store = MemorySnapshotStore()
        store.save(["cached"], key: "tickets.t1")

        let fetch = ControlledFetch(gated: true, results: [.success(["fresh"])])
        let resource = Resource(cacheKey: "tickets.t1", store: store) { try await fetch() }

        let loading = Task { await resource.load(maxWait: .seconds(5)) }
        await eventually { resource.value != nil }
        #expect(resource.value == ["cached"])

        fetch.release()
        await loading.value
        #expect(resource.value == ["fresh"])
        #expect(store.load([String].self, key: "tickets.t1")?.value == ["fresh"])
    }

    @Test("An optimistic set clears the error and is cached")
    func optimisticSet() async {
        let store = MemorySnapshotStore()
        let fetch = ControlledFetch(gated: false, results: [.failure(.timeout)])
        let resource = Resource(cacheKey: "k", store: store) { try await fetch() }
        await resource.refresh()
        #expect(resource.error == .timeout)
        resource.set(["local"])
        #expect(resource.error == nil)
        #expect(store.load([String].self, key: "k")?.value == ["local"])
    }

    @Test("File snapshots round-trip and survive a new store instance")
    func fileStore() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        FileSnapshotStore(directory: dir).save(["x", "y"], key: "teams/list")
        let loaded = try #require(FileSnapshotStore(directory: dir).load([String].self, key: "teams/list"))
        #expect(loaded.value == ["x", "y"])
        #expect(abs(loaded.savedAt.timeIntervalSinceNow) < 5)
    }

    @Test("A refetch after a write ignores the fetch already in flight and gets fresh data")
    func refetchAfterWrite() async {
        let fetch = ControlledFetch(gated: true, results: [.success(["before write"]), .success(["after write"])])
        let resource = Resource<[String]> { try await fetch() }

        // A poll is in flight, started before the write.
        let poll = Task { await resource.refresh() }
        await eventually { fetch.calls == 1 }

        // The write lands; its result is shown at once, then refetched.
        resource.set(["optimistic"])
        let refetch = Task { await resource.refetch() }
        fetch.release()
        await poll.value
        await refetch.value
        await eventually { fetch.calls == 2 && resource.value == ["after write"] }

        #expect(fetch.calls == 2)
        #expect(resource.value == ["after write"])
    }

    @Test("Concurrent refetches share the one fetch queued behind the poll")
    func concurrentRefetchesShare() async {
        let fetch = ControlledFetch(gated: true, results: [.success(["poll"]), .success(["fresh"])])
        let resource = Resource<[String]> { try await fetch() }
        let poll = Task { await resource.refresh() }
        await eventually { fetch.calls == 1 }

        let a = Task { await resource.refetch() }
        let b = Task { await resource.refetch() }
        await eventually { true }
        fetch.release()
        await poll.value; await a.value; await b.value
        await eventually { resource.value == ["fresh"] }

        #expect(fetch.calls == 2)
        #expect(resource.value == ["fresh"])
    }

    @Test("The cached copy can be shown before any fetch starts")
    func showCachedFirst() async {
        let store = MemorySnapshotStore()
        store.save(["cached"], key: "k")
        let fetch = ControlledFetch(gated: true, results: [.success(["fresh"])])
        let resource = Resource<[String]>(cacheKey: "k", store: store) { try await fetch() }
        #expect(resource.showCached())
        #expect(resource.value == ["cached"])
        #expect(fetch.calls == 0)
        #expect(Resource<[String]>(cacheKey: "none", store: store) { [] }.showCached() == false)
    }

    @Test("The default wait leaves room under the 6-second promise")
    func defaultWait() {
        #expect(Resource<[String]>.maxWait < .seconds(6))
        #expect(Resource<[String]>.maxWait >= .seconds(5))
    }
}
