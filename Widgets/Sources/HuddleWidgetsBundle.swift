import SwiftUI
import WidgetKit

@main
struct HuddleWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        ShiftLiveActivityWidget()
        ShiftControl()
        BreakControl()
    }
}
