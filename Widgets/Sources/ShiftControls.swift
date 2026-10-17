import AppIntents
import HuddleKit
import SwiftUI
import WidgetKit

/// Control Center: a Shift toggle (on = on the clock) and a Break button.

struct ShiftValueProvider: ControlValueProvider {
    var previewValue: Bool { true }

    func currentValue() async throws -> Bool {
        SharedContainer.snapshot.isOnShift
    }
}

/// Turning the toggle on starts the day; off ends it.
struct SetShiftIntent: SetValueIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Set Shift"
    /// Runs in the background, but may come forward to write a plan or wrap-up.
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]
    @Parameter(title: "On the clock") var value: Bool

    func perform() async throws -> some IntentResult {
        let on = value
        try await ShiftIntentRunner.run(self) { actions in
            if on { try await ShiftIntentRunner.startDay(self, actions) } else { try await actions.endDay() }
        }
        return .result()
    }
}

struct ShiftControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "ShiftControl", provider: ShiftValueProvider()) { isOn in
            ControlWidgetToggle("Shift", isOn: isOn, action: SetShiftIntent()) { on in
                Label(on ? "Working" : "Off the clock", systemImage: on ? "clock.fill" : "clock")
            }
            .tint(WidgetPalette.lime)
        }
        .displayName("Shift")
        .description("Start or end your day.")
    }
}

/// One button: take a break when working, back to work when on one.
struct BreakIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Break"

    func perform() async throws -> some IntentResult {
        let onBreak = SharedContainer.snapshot.phase == .onBreak
        try await ShiftIntentRunner.run(self) { onBreak ? try await $0.resume() : try await $0.takeBreak() }
        return .result()
    }
}

struct BreakControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "BreakControl") {
            ControlWidgetButton(action: BreakIntent()) {
                Label("Break", systemImage: "cup.and.saucer")
            }
        }
        .displayName("Break")
        .description("Take a break, or end the one you’re on.")
    }
}
