import Foundation
import HuddleKit
#if canImport(WidgetKit)
import WidgetKit
#endif

/// What the app and its extension (widgets, controls, Live Activity) share
/// through the App Group: the session in the keychain, the selected team,
/// and the latest shift snapshot.
enum SharedContainer {
    static let appGroupID: String = Bundle.main.object(forInfoDictionaryKey: "HNAppGroupID") as? String
        ?? "group.com.sarkarshubhdeep.huddlenative"

    static var defaults: UserDefaults { UserDefaults(suiteName: appGroupID) ?? .standard }

    /// The keychain group the app and extension share (`<team>.<bundle id>.shared`).
    static let keychainGroup: String? = Bundle.main.object(forInfoDictionaryKey: "HNKeychainGroup") as? String

    /// The keychain the app and extension both read.
    static var keychain: any SecretStore {
        KeychainStore(service: "HuddleNative", accessGroup: keychainGroup)
    }

    // MARK: Session

    /// The signed-in session, read straight from the shared keychain.
    static var session: Session? {
        guard let data = try? keychain.read("session") else { return nil }
        let session = try? JSONDecoder().decode(Session.self, from: data)
        return session?.isExpired() == false ? session : nil
    }

    static func actions() -> ShiftActions? {
        guard let session else { return nil }
        let token = session.token
        let api = APIClient(endpoint: session.endpoint, token: { token })
        return ShiftActions(api: api, userId: session.userId)
    }

    // MARK: Team

    private enum Key {
        static let teamId = "shared.teamId", teamNames = "shared.teamNames", snapshot = "shared.snapshot"
    }

    /// The team the app has selected; Start day from outside the app uses it.
    static var teamId: String? {
        get { defaults.string(forKey: Key.teamId) }
        set { defaults.set(newValue, forKey: Key.teamId) }
    }

    /// Teams that ask for a plan before clocking in.
    static var planTeams: Set<String> {
        get { Set(defaults.stringArray(forKey: "shared.planTeams") ?? []) }
        set { defaults.set(Array(newValue), forKey: "shared.planTeams") }
    }

    /// A sheet an intent asked the app to show when it comes forward.
    enum PendingSheet: String { case plan, wrapUp }

    static var pendingSheet: PendingSheet? {
        get { defaults.string(forKey: "shared.pendingSheet").flatMap(PendingSheet.init(rawValue:)) }
        set { defaults.set(newValue?.rawValue, forKey: "shared.pendingSheet") }
    }

    static var teamNames: [String: String] {
        get { defaults.dictionary(forKey: Key.teamNames) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: Key.teamNames) }
    }

    // MARK: Snapshot

    static var snapshot: ShiftSnapshot {
        guard let data = defaults.data(forKey: Key.snapshot),
              let snapshot = try? JSONDecoder().decode(ShiftSnapshot.self, from: data) else { return .signedOut }
        return snapshot
    }

    /// Saves `snapshot` and, when it changed, reloads the widgets and controls.
    static func publish(_ snapshot: ShiftSnapshot) {
        guard snapshot != self.snapshot || defaults.data(forKey: Key.snapshot) == nil else { return }
        defaults.set(try? JSONEncoder().encode(snapshot), forKey: Key.snapshot)
        reloadWidgets()
    }

    static func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
        #endif
    }

    static func clear() {
        defaults.removeObject(forKey: Key.snapshot)
        defaults.removeObject(forKey: Key.teamId)
        defaults.removeObject(forKey: Key.teamNames)
        defaults.removeObject(forKey: "shared.planTeams")
        defaults.removeObject(forKey: "shared.pendingSheet")
        reloadWidgets()
    }

    /// Fetches the current state, publishes it, and returns it.
    @discardableResult
    static func refresh() async throws -> ShiftSnapshot {
        guard let actions = actions() else {
            publish(.signedOut)
            return .signedOut
        }
        let names = teamNames
        let snapshot = try await actions.snapshot(teamName: { names[$0] })
        publish(snapshot)
        return snapshot
    }
}

extension Notification.Name {
    /// Posted in the app after an intent changed the shift, so open screens refetch.
    static let shiftChangedOutsideApp = Notification.Name("HuddleShiftChangedOutsideApp")
}
