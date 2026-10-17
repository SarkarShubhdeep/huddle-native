import Foundation

/// Which team the app opens on.
public enum TeamChoice {
    /// The team you last picked, if you're still in it. Otherwise your first
    /// shared team, since the personal team is rarely where the work is; and
    /// the personal team only when it's all you have.
    public static func restore(from teams: [Team], savedId: String?) -> Team? {
        if let savedId, let saved = teams.first(where: { $0.id == savedId }) { return saved }
        return teams.first { !$0.isPersonal } ?? teams.first
    }
}
