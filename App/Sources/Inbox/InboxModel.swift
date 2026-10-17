import Foundation
import HuddleKit
import Observation

/// Your notifications and the unread count for the dock's badge. Lives for
/// the signed-in session; refreshes when the app becomes active and every
/// 30 s while it's in front.
@MainActor
@Observable
final class InboxModel {
    let inbox: Resource<[AppNotification]>
    var error: String?

    @ObservationIgnored private let service: NotificationService

    init(api: APIClient, userId: String, snapshots: any SnapshotStore) {
        let service = NotificationService(api)
        self.service = service
        inbox = Resource(cacheKey: "inbox.\(userId)", store: snapshots) { try await service.inbox() }
    }

    var notifications: [AppNotification] { inbox.value ?? [] }
    var unreadCount: Int { notifications.filter { !$0.read }.count }

    func refresh() async { await inbox.refresh() }

    // MARK: Actions (optimistic, then confirmed)

    func markRead(_ notification: AppNotification) async {
        guard !notification.read else { return }
        update { list in
            if let i = list.firstIndex(where: { $0.id == notification.id }) { list[i].read = true }
        }
        await run { try await self.service.markRead(notification.id) }
    }

    func markAllRead() async {
        update { list in for i in list.indices { list[i].read = true } }
        await run { try await self.service.markAllRead() }
    }

    func delete(_ notifications: [AppNotification]) async {
        let ids = Set(notifications.map(\.id))
        update { list in list.removeAll { ids.contains($0.id) } }
        await run { _ = try await self.service.delete(Array(ids)) }
    }

    private func update(_ change: (inout [AppNotification]) -> Void) {
        var list = notifications
        change(&list)
        inbox.set(list)
    }

    private func run(_ write: @escaping () async throws -> Void) async {
        error = nil
        do { try await write() } catch { self.error = APIError.from(error).localizedDescription }
        await inbox.refetch()
    }
}
