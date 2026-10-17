import Foundation
import HuddleKit

/// How times are written on screen and read by VoiceOver.
enum ShiftClockFormat {
    /// `3:42:18`. Same format as HuddleKit, so the app and widgets agree.
    static func clock(_ seconds: Int) -> String { ShiftClock.clockString(seconds) }

    /// `7h 51m`, for totals.
    static func duration(_ seconds: Int) -> String { ShiftClock.durationString(seconds) }

    /// "3 hours, 42 minutes", for VoiceOver.
    static func spoken(_ seconds: Int) -> String {
        Duration.seconds(max(0, seconds) / 60 * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: .wide, zeroValueUnits: .hide))
            .ifEmpty("0 minutes")
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
