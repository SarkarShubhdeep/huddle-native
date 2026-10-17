import SwiftUI
import WidgetKit

@main
struct HuddleWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
    }
}

/// Step 1 placeholder so the extension target builds and embeds.
/// The real Today widget, Control Center controls and Live Activity arrive in Step 10.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Today", provider: TodayProvider()) { _ in
            VStack(alignment: .leading, spacing: 2) {
                Text("Today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("—")
                    .font(.system(.title, design: .rounded, weight: .semibold))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Hours worked today.")
        .supportedFamilies([.systemSmall])
    }
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry { SimpleEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(SimpleEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        completion(Timeline(entries: [SimpleEntry(date: .now)], policy: .never))
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
}
