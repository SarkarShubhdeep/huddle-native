import Foundation
import Synchronization

/// The last good copy of a screen's data, so the app opens on real content
/// instead of a spinner and keeps showing it when a refresh fails.
public protocol SnapshotStore: Sendable {
    func load<T: Decodable>(_ type: T.Type, key: String) -> Snapshot<T>?
    func save<T: Encodable>(_ value: T, key: String)
    func removeAll()
}

public struct Snapshot<T> {
    public let value: T
    public let savedAt: Date
}

/// One small JSON file per key, under Caches (the OS may purge it; that's fine).
public struct FileSnapshotStore: SnapshotStore {
    private let directory: URL

    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.directory = base.appendingPathComponent("Snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    public func load<T: Decodable>(_ type: T.Type, key: String) -> Snapshot<T>? {
        guard let data = try? Data(contentsOf: file(key)) else { return nil }
        return Self.decode(type, data)
    }

    public func save<T: Encodable>(_ value: T, key: String) {
        guard let data = Self.encode(value) else { return }
        try? data.write(to: file(key), options: .atomic)
    }

    public func removeAll() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func file(_ key: String) -> URL {
        let safe = key.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" }
        return directory.appendingPathComponent(String(safe) + ".json")
    }

    static func encode<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(EncodableBox(savedAt: .now, value: value))
    }

    static func decode<T: Decodable>(_ type: T.Type, _ data: Data) -> Snapshot<T>? {
        guard let box = try? JSONDecoder().decode(DecodableBox<T>.self, from: data) else { return nil }
        return Snapshot(value: box.value, savedAt: box.savedAt)
    }
}

/// For tests and previews.
public final class MemorySnapshotStore: SnapshotStore {
    private let items = Mutex<[String: Data]>([:])

    public init() {}

    public func load<T: Decodable>(_ type: T.Type, key: String) -> Snapshot<T>? {
        items.withLock { $0[key] }.flatMap { FileSnapshotStore.decode(type, $0) }
    }

    public func save<T: Encodable>(_ value: T, key: String) {
        guard let data = FileSnapshotStore.encode(value) else { return }
        items.withLock { $0[key] = data }
    }

    public func removeAll() {
        items.withLock { $0.removeAll() }
    }
}

private struct EncodableBox<T: Encodable>: Encodable {
    let savedAt: Date
    let value: T
}

private struct DecodableBox<T: Decodable>: Decodable {
    let savedAt: Date
    let value: T
}
