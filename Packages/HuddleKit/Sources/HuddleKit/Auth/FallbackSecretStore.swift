import Foundation

/// Reads from `primary`, and when a key is only in `legacy`, moves it over.
/// Used to move the session from the app's own keychain into the one it
/// shares with its widgets, without signing anyone out.
public struct FallbackSecretStore: SecretStore {
    private let primary: any SecretStore
    private let legacy: any SecretStore

    public init(primary: any SecretStore, legacy: any SecretStore) {
        self.primary = primary
        self.legacy = legacy
    }

    public func read(_ key: String) throws -> Data? {
        if let data = try? primary.read(key) { return data }
        guard let data = try legacy.read(key) else { return nil }
        // Best effort: if the move fails, the legacy copy still works.
        if (try? primary.write(data, for: key)) != nil { try? legacy.delete(key) }
        return data
    }

    public func write(_ data: Data, for key: String) throws {
        try primary.write(data, for: key)
    }

    public func delete(_ key: String) throws {
        try primary.delete(key)
        try? legacy.delete(key)
    }
}
