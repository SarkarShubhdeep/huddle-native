import Foundation
import HuddleKit
import Observation

/// App-wide state: who's signed in, where, and which team is active.
@MainActor
@Observable
final class AppModel {
    let session: SessionStore

    /// Your teams, cached per user so they show instantly (and offline) next launch.
    private(set) var teams: Resource<[Team]>?
    /// You, for the avatar.
    private(set) var me: PublicUser?
    /// The active team. Clock actions still use the active shift's team (Step 5).
    private(set) var team: Team?

    @ObservationIgnored private let snapshots: any SnapshotStore
    @ObservationIgnored private let defaults: UserDefaults

    /// Every request this session sends, for Settings › Diagnostics.
    let requestLog: RequestLog

    init(
        session: SessionStore? = nil,
        requestLog: RequestLog = RequestLog(),
        snapshots: any SnapshotStore = FileSnapshotStore(),
        defaults: UserDefaults = .standard
    ) {
        self.requestLog = requestLog
        self.session = session ?? SessionStore(
            // Shared with the widgets; a session saved before Step 10 moves over on first read.
            secrets: FallbackSecretStore(primary: SharedContainer.keychain, legacy: KeychainStore()),
            transport: LoggingTransport(URLSessionTransport(), log: requestLog)
        )
        self.snapshots = snapshots
        self.defaults = defaults
    }

    /// On launch: restore the saved session, then the account behind it.
    func start() async {
        session.restore()
        if session.session != nil { await loadAccount() }
    }

    func signIn(email: String, password: String, endpoint: ServerEndpoint) async throws {
        try await session.signIn(email: email, password: password, endpoint: endpoint)
        defaults.set(email.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "signIn.lastEmail")
        await loadAccount()
    }

    func signOut() {
        session.signOut()
        requestLog.clear()
        SharedContainer.clear()
        Task { await ShiftLiveActivity.sync(.signedOut) }
        teams = nil
        team = nil
        me = nil
    }

    /// An API client for the signed-in user.
    var api: APIClient? { session.makeClient() }
    var userId: String? { session.session?.userId }
    var snapshotStore: any SnapshotStore { snapshots }

    /// The shift model for the signed-in user, or nil when signed out.
    func makeNowModel() -> NowModel? {
        guard let current = session.session, let api = session.makeClient() else { return nil }
        return NowModel(api: api, userId: current.userId, snapshots: snapshots)
    }

    var lastEmail: String { defaults.string(forKey: "signIn.lastEmail") ?? "" }

    // MARK: Teams

    func select(_ team: Team) {
        self.team = team
        SharedContainer.teamId = team.id
        if let userId = session.session?.userId {
            defaults.set(team.id, forKey: Self.teamKey(userId))
        }
    }

    func refreshTeams() async {
        await teams?.refresh()
        restoreTeam()
    }

    private func loadAccount() async {
        guard let current = session.session, let api = session.makeClient() else { return }
        let teamService = TeamService(api)
        let resource = Resource<[Team]>(cacheKey: "teams.\(current.userId)", store: snapshots) {
            try await teamService.list()
        }
        teams = resource
        let userId = current.userId
        let users = UserService(api)
        let profile = Resource<PublicUser>(cacheKey: "me.\(userId)", store: snapshots) { try await users.get(userId) }
        // Cached copies are enough to show the team and your avatar right
        // away, even when the server is slow or down; refreshes follow.
        if resource.showCached() { restoreTeam() }
        if profile.showCached() { me = profile.value }
        async let loadTeams: Void = resource.load()
        async let loadProfile: Void = profile.load()
        _ = await (loadTeams, loadProfile)
        restoreTeam()
        me = profile.value ?? me
    }

    private func restoreTeam() {
        guard let list = teams?.value, let userId = session.session?.userId else { return }
        let savedId = team?.id ?? defaults.string(forKey: Self.teamKey(userId))
        team = TeamChoice.restore(from: list, savedId: savedId)
        SharedContainer.teamId = team?.id
        SharedContainer.teamNames = Dictionary(list.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        SharedContainer.planTeams = Set(list.filter(\.requiresPlan).map(\.id))
    }

    private static func teamKey(_ userId: String) -> String { "team.\(userId)" }
}
