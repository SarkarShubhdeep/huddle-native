import SwiftUI

/// A one-pixel separator in the hairline color.
struct Hairline: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: 1 / displayScale)
            .accessibilityHidden(true)
    }
}

/// Rows that run edge to edge, separated by hairlines, with no box around them.
/// For short lists inside a scroll view (Today on the Now screen). Long lists
/// use `List` with `.listStyle(.plain)`, which draws the same thing natively.
struct EdgeToEdgeList<Content: View>: View {
    /// Where separators start, measured from the leading edge.
    var separatorInset: CGFloat = 0
    /// Hairlines above the first row and below the last.
    var outerHairlines = true
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            if outerHairlines { Hairline() }
            Group(subviews: content) { rows in
                ForEach(rows.indices, id: \.self) { index in
                    if index > 0 { Hairline().padding(.leading, separatorInset) }
                    rows[index]
                }
            }
            if outerHairlines { Hairline() }
        }
    }
}

// MARK: - Ticket status

/// How a ticket's status reads and which color its dot takes.
enum TicketStatus: String, CaseIterable, Sendable {
    case open
    case inProgress = "in-progress"
    case blocked
    case reviewed
    case closed

    init(raw: String) { self = TicketStatus(rawValue: raw) ?? .open }

    var label: String {
        switch self {
        case .open: "Open"
        case .inProgress: "In progress"
        case .blocked: "Blocked"
        case .reviewed: "In review"
        case .closed: "Done"
        }
    }

    var color: Color {
        switch self {
        case .open: Palette.textSecondary
        case .inProgress: Palette.limeText
        case .blocked: Palette.destructive
        case .reviewed: Palette.breakText
        case .closed: Palette.done
        }
    }
}

// MARK: - Rows

/// A ticket in the Tickets list: status dot, title, a line of facts, and a
/// play/pause button. The row whose timer is running is tinted lime.
struct TicketRow: View {
    let title: String
    let status: TicketStatus
    var priority: String?
    var assigneeInitials: [String] = []
    /// "Now 0:42:10 · today 2:58", "Today 1:15", "No time yet".
    var timeText: String
    var isRunning = false
    var onToggleTimer: () -> Void = {}

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
            Circle()
                .fill(status.color)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Palette.textPrimary)
                meta
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            Button(isRunning ? "Pause timer" : "Start timer", systemImage: isRunning ? "pause.fill" : "play.fill", action: onToggleTimer)
                .labelStyle(.iconOnly)
                .buttonStyle(HNIconButtonStyle(role: isRunning ? .primary : .secondary))
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 6 }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, Spacing.xl)
    }

    private var meta: some View {
        // Wraps onto more lines rather than truncating.
        FlowLayout(spacing: Spacing.s, lineSpacing: Spacing.xxs) { metaItems }
        .font(.footnote)
        .foregroundStyle(Palette.textSecondary)
    }

    @ViewBuilder private var metaItems: some View {
        Text(status.label).fontWeight(.semibold).foregroundStyle(status.color)
        if let priority { Text(priority) }
        if !assigneeInitials.isEmpty {
            HStack(spacing: -4) {
                ForEach(assigneeInitials, id: \.self) { Avatar(initials: $0, size: 20) }
            }
            .accessibilityLabel("Assigned to \(assigneeInitials.joined(separator: ", "))")
        }
        Text(timeText)
            .monospacedDigit()
            .fontWeight(isRunning ? .semibold : .regular)
            .foregroundStyle(isRunning ? Palette.limeText : Palette.textSecondary)
    }
}

/// A tinted background for the ticket whose timer is running.
extension View {
    func runningRowBackground(_ isRunning: Bool) -> some View {
        background(isRunning ? Palette.limeSoft : .clear)
    }
}

/// A line of work: dot, title, duration. Used for Today on the Now screen.
struct WorkRow: View {
    let title: String
    let duration: String
    var isActive = false

    var body: some View {
        HStack(spacing: Spacing.m) {
            Circle()
                .fill(isActive ? Palette.limeText : Palette.textSecondary)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(title)
                .font(.body)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(duration)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(.vertical, Spacing.m)
        .padding(.horizontal, Spacing.xl)
        .accessibilityElement(children: .combine)
    }
}

/// A timesheet entry: a colored bar, what it was, when, and how long.
struct TimeRow: View {
    let title: String
    let when: String
    let duration: String
    var tone: Tone = .neutral
    var isEmphasized = false

    var body: some View {
        HStack(spacing: Spacing.m) {
            RoundedRectangle(cornerRadius: 2)
                .fill(tone == .neutral ? Palette.textSecondary : tone.foreground)
                .frame(width: 4, height: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.body.weight(isEmphasized ? .semibold : .regular))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Text(when)
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(duration)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, Spacing.xl)
        .accessibilityElement(children: .combine)
    }
}

/// Initials in a circle. The current user gets the lime tint.
struct Avatar: View {
    let initials: String
    var size: CGFloat = 36
    var isMe = false

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.36, weight: .bold))
            .foregroundStyle(isMe ? Palette.limeText : Palette.textSecondary)
            .frame(width: size, height: size)
            .background(isMe ? Palette.limeSoft : Palette.fill, in: Circle())
            .overlay(Circle().stroke(Palette.canvas, lineWidth: size < 24 ? 1.5 : 0))
            .accessibilityHidden(true)
    }
}

// MARK: - Previews

struct RowsPreview: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                Text("Tickets").font(Typography.sectionTitle).padding(.horizontal, Spacing.margin)
                EdgeToEdgeList(separatorInset: 42, outerHairlines: false) {
                    TicketRow(title: "Fix login redirect on iPad", status: .inProgress, priority: "High",
                              assigneeInitials: ["SD"], timeText: "Now 0:42:10 · today 2:58", isRunning: true)
                        .runningRowBackground(true)
                    TicketRow(title: "Review onboarding copy", status: .open, priority: "Medium",
                              assigneeInitials: ["SD"], timeText: "Today 1:15")
                    TicketRow(title: "Timesheet export shows UTC instead of the team time zone", status: .blocked,
                              priority: "High", assigneeInitials: ["SD", "AK"], timeText: "No time yet")
                    TicketRow(title: "Rename team settings labels", status: .reviewed, priority: "Low", timeText: "Tue 1:05")
                    TicketRow(title: "Release notes for 1.0.8", status: .closed, priority: "No priority", timeText: "Wed 0:50")
                }
                Text("Today").font(Typography.sectionTitle).padding(.horizontal, Spacing.margin)
                EdgeToEdgeList {
                    WorkRow(title: "Fix login redirect on iPad", duration: "0:42", isActive: true)
                    WorkRow(title: "Review onboarding copy", duration: "1:15")
                    WorkRow(title: "Standup notes", duration: "1:15")
                }
                Text("Thursday").font(Typography.sectionTitle).padding(.horizontal, Spacing.margin)
                EdgeToEdgeList {
                    TimeRow(title: "Shift", when: "9:02 AM – now", duration: "3:42", tone: .working, isEmphasized: true)
                    TimeRow(title: "Rest break · paid", when: "11:30 – 11:42 AM", duration: "0:12", tone: .onBreak)
                    TimeRow(title: "Standup notes", when: "9:02 – 10:15 AM", duration: "1:13")
                }
            }
            .padding(.vertical, Spacing.l)
        }
        .background(Palette.canvas)
    }
}

#Preview("Light") { RowsPreview() }
#Preview("Dark") { RowsPreview().preferredColorScheme(.dark) }
