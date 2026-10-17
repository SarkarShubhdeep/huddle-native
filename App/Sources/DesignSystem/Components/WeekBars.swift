import SwiftUI

/// The timesheet's week card: the week total, then one bar per day. Tap a bar
/// to pick that day. The bars compare days; they aren't progress toward a goal.
struct WeekBars: View {
    struct Day: Hashable {
        /// "M", "T", ...
        let shortName: String
        /// "Monday", for VoiceOver.
        let fullName: String
        let seconds: Int
    }

    let days: [Day]
    @Binding var selectedIndex: Int
    /// "4 days · avg 6h 46m"
    var caption: String?
    /// "This week", or the dates of a past week.
    var title = "This week"

    /// Bars scale to the longest day, but never less than a 9-hour day, so a
    /// short week doesn't look full.
    private var scaleSeconds: Int { max(9 * 3600, days.map(\.seconds).max() ?? 0) }
    private let barArea: CGFloat = 106

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            let header = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs))
                : AnyLayout(HStackLayout(alignment: .bottom))
            header {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title).font(.footnote).foregroundStyle(Palette.textSecondary)
                    Text(ShiftClockFormat.duration(days.map(\.seconds).reduce(0, +)))
                        .font(Typography.time(.largeTitle))
                        .foregroundStyle(Palette.textPrimary)
                        .contentTransition(.numericText())
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityValue(ShiftClockFormat.spoken(days.map(\.seconds).reduce(0, +)))
                Spacer(minLength: 0)
                if let caption {
                    Text(caption)
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                }
            }
            HStack(alignment: .bottom, spacing: Spacing.s) {
                ForEach(days.indices, id: \.self) { index in
                    bar(index)
                }
            }
        }
        .padding(.top, 18)
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.hero))
    }

    private func bar(_ index: Int) -> some View {
        let day = days[index]
        let isSelected = index == selectedIndex
        let height = max(6, barArea * CGFloat(day.seconds) / CGFloat(scaleSeconds))
        return Button {
            selectedIndex = index
        } label: {
            VStack(spacing: 6) {
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Palette.lime : Palette.bar)
                    .frame(height: height)
                Text(day.shortName)
                    .font(.caption.weight(isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? Palette.textPrimary : Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 132)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .springAnimation(value: height)
        .accessibilityLabel(day.fullName)
        .accessibilityValue(ShiftClockFormat.spoken(day.seconds))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension WeekBars.Day {
    /// Monday-first sample week (Thursday in progress).
    static let sampleWeek: [WeekBars.Day] = zip(
        zip(["M", "T", "W", "T", "F", "S", "S"],
            ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]),
        [28080, 29160, 27000, 13320, 0, 0, 0]
    ).map { WeekBars.Day(shortName: $0.0, fullName: $0.1, seconds: $1) }
}

// MARK: - Previews

struct WeekBarsPreview: View {
    @State private var selected = 3

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                WeekBars(days: WeekBars.Day.sampleWeek, selectedIndex: $selected, caption: "4 days · avg 6h 46m")
                SectionHeader(title: WeekBars.Day.sampleWeek[selected].fullName,
                              detail: ShiftClockFormat.duration(WeekBars.Day.sampleWeek[selected].seconds))
                EdgeToEdgeList {
                    TimeRow(title: "Shift", when: "9:02 AM – now", duration: "3:42", tone: .working, isEmphasized: true)
                    TimeRow(title: "Fix login redirect on iPad", when: "11:42 AM – now", duration: "0:42", tone: .working)
                    TimeRow(title: "Rest break · paid", when: "11:30 – 11:42 AM", duration: "0:12", tone: .onBreak)
                    TimeRow(title: "Review onboarding copy", when: "10:15 – 11:30 AM", duration: "1:15")
                    TimeRow(title: "Standup notes", when: "9:02 – 10:15 AM", duration: "1:13")
                }
                .padding(.horizontal, -Spacing.margin)
            }
            .padding(Spacing.margin)
        }
        .background(Palette.canvas)
    }
}

#Preview("Light") { WeekBarsPreview() }
#Preview("Dark") { WeekBarsPreview().preferredColorScheme(.dark) }
