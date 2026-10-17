import ActivityKit
import Foundation
import HuddleKit

/// The Live Activity for an open shift. Its state is the shift snapshot, so
/// the lock screen and Dynamic Island tick on the device without pushes.
struct ShiftActivityAttributes: ActivityAttributes {
    typealias ContentState = ShiftSnapshot
    var teamName: String
}

/// Starts, updates and ends the shift's Live Activity to match a snapshot.
/// Only the app can do this, so intents that change the shift run in the app.
enum ShiftLiveActivity {
    static func sync(_ snapshot: ShiftSnapshot) async {
        let current = Activity<ShiftActivityAttributes>.activities
        guard snapshot.isOnShift else {
            for activity in current {
                await activity.end(ActivityContent(state: snapshot, staleDate: nil), dismissalPolicy: .immediate)
            }
            return
        }
        let content = ActivityContent(state: snapshot, staleDate: nil)
        if let activity = current.first {
            if activity.content.state != snapshot { await activity.update(content) }
            for extra in current.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        _ = try? Activity.request(
            attributes: ShiftActivityAttributes(teamName: snapshot.teamName ?? "Huddle"),
            content: content,
            pushType: nil
        )
    }
}
