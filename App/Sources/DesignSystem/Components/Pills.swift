import SwiftUI

/// The look of a GitHub-style dropdown pill. Active pills (a filter that's
/// narrowing the list) are tinted lime with a lime edge.
private struct PillLabel: View {
    let title: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Text(title)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.heavy))
                .accessibilityHidden(true)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(isActive ? Palette.limeText : Palette.textPrimary)
        .padding(.leading, 13)
        .padding(.trailing, 10)
        .frame(minHeight: 34)
        .background(isActive ? Palette.limeSoft : Palette.fill, in: Capsule())
        .overlay(Capsule().strokeBorder(isActive ? Palette.limeText : .clear, lineWidth: 1))
        .contentShape(Capsule())
    }
}

/// A dropdown pill that opens a native (glass) menu.
struct FilterPill<MenuContent: View>: View {
    let title: String
    var isActive = false
    @ViewBuilder var menu: MenuContent

    var body: some View {
        Menu { menu } label: { PillLabel(title: title, isActive: isActive) }
            .buttonStyle(.plain)
            .accessibilityValue(isActive ? "Active" : "")
    }
}

/// A multi-select filter (priority, assignee): the menu stays open while you
/// tick options, and the pill shows how many are on.
struct MultiSelectPill<Option: Hashable & Identifiable>: View {
    let title: String
    let options: [Option]
    let label: (Option) -> String
    @Binding var selection: Set<Option>

    var body: some View {
        FilterPill(title: selection.isEmpty ? title : "\(title) · \(selection.count)", isActive: !selection.isEmpty) {
            ForEach(options) { option in
                Toggle(label(option), isOn: Binding(
                    get: { selection.contains(option) },
                    set: { isOn in
                        if isOn { selection.insert(option) } else { selection.remove(option) }
                    }
                ))
            }
            if !selection.isEmpty {
                Divider()
                Button("Clear", role: .destructive) { selection.removeAll() }
            }
        }
        .menuActionDismissBehavior(.disabled)
    }
}

/// One way to sort, with the words for each direction ("Newest first").
struct SortOption<Key: Hashable>: Identifiable {
    let key: Key
    let title: String
    var descending = "Newest first"
    var ascending = "Oldest first"
    var id: Key { key }
}

/// The Sort pill. Its menu picks the field and, below a divider, the direction.
struct SortPill<Key: Hashable>: View {
    let options: [SortOption<Key>]
    @Binding var key: Key
    @Binding var ascending: Bool

    private var current: SortOption<Key>? { options.first { $0.key == key } }

    var body: some View {
        FilterPill(title: "Sort") {
            Section("Sort by") {
                Picker("Sort by", selection: $key) {
                    ForEach(options) { Text($0.title).tag($0.key) }
                }
                .pickerStyle(.inline)
            }
            if let current {
                Picker("Order", selection: $ascending) {
                    Text(current.descending).tag(false)
                    Text(current.ascending).tag(true)
                }
                .pickerStyle(.inline)
            }
        }
        .accessibilityValue(current.map { "\($0.title), \(ascending ? $0.ascending : $0.descending)" } ?? "")
    }
}

/// The leading "filters" pill: inverted, with the number of active filters.
struct FilterCountPill: View {
    let activeCount: Int
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "line.3.horizontal.decrease")
                if activeCount > 0 { Text("\(activeCount)") }
            }
            .font(.footnote.weight(.bold))
            .foregroundStyle(Palette.canvas)
            .padding(.horizontal, 10)
            .frame(minHeight: 34)
            .background(Palette.textPrimary, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filters")
        .accessibilityValue(activeCount == 1 ? "1 active" : "\(activeCount) active")
    }
}

/// A horizontally scrolling row of pills that runs edge to edge.
struct PillBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.s) { content }
                .padding(.horizontal, Spacing.margin)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Previews

struct PillsPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Bar()
            Text("6 tickets · Recently updated first")
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
                .padding(.horizontal, Spacing.margin)
        }
        .padding(.vertical, Spacing.l)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.canvas)
    }

    /// The Tickets screen's pill row with sample filters.
    struct Bar: View {
        enum Priority: String, CaseIterable, Identifiable {
            case critical = "Critical", high = "High", medium = "Medium", low = "Low", none = "None"
            var id: String { rawValue }
        }

        enum Sort: Hashable { case updated, created, priority, time, title }

        @State private var priorities: Set<Priority> = [.high, .critical]
        @State private var sort: Sort = .updated
        @State private var ascending = false
        @State private var status = "Open"

        private let sorts: [SortOption<Sort>] = [
            SortOption(key: .updated, title: "Recently updated"),
            SortOption(key: .created, title: "Created"),
            SortOption(key: .priority, title: "Priority", descending: "Highest first", ascending: "Lowest first"),
            SortOption(key: .time, title: "Time spent today", descending: "Most first", ascending: "Least first"),
            SortOption(key: .title, title: "Title", descending: "Z to A", ascending: "A to Z"),
        ]

        var body: some View {
            PillBar {
                FilterCountPill(activeCount: 2 + (priorities.isEmpty ? 0 : 1))
                FilterPill(title: status, isActive: status != "All") {
                    Picker("Status", selection: $status) {
                        ForEach(["All", "Open", "In progress", "Blocked", "In review", "Done"], id: \.self) { Text($0) }
                    }
                }
                FilterPill(title: "Assignee: Me", isActive: true) {
                    Button("Me") {}
                    Button("Anyone") {}
                }
                MultiSelectPill(title: "Priority", options: Priority.allCases, label: \.rawValue, selection: $priorities)
                SortPill(options: sorts, key: $sort, ascending: $ascending)
            }
        }
    }
}

#Preview("Light") { PillsPreview() }
#Preview("Dark") { PillsPreview().preferredColorScheme(.dark) }
