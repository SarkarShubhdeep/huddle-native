import HuddleKit
import SwiftUI
import UIKit

/// The few design tokens the extension needs (it can't see the app's asset catalog).
enum WidgetPalette {
    static let lime = Color(red: 0xC6 / 255, green: 0xF1 / 255, blue: 0x35 / 255)
    static let onLime = Color(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255)
    static let limeText = dynamic(light: 0x4D7A0C, dark: 0xC6F135)
    static let breakText = dynamic(light: 0x8F5300, dark: 0xFFB340)
    static let done = dynamic(light: 0x1F8A3A, dark: 0x30D158)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? color(dark) : color(light) })
    }

    private static func color(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension ShiftSnapshot {
    var label: String {
        switch phase {
        case .offClock: "Off the clock"
        case .working: "Working"
        case .onBreak: "On break"
        case .dayDone: "Day done"
        }
    }

    var tint: Color {
        switch phase {
        case .working: WidgetPalette.limeText
        case .onBreak: WidgetPalette.breakText
        case .dayDone: WidgetPalette.done
        case .offClock: .secondary
        }
    }

    var symbol: String {
        switch phase {
        case .offClock: "sun.max"
        case .working: "clock"
        case .onBreak: "cup.and.saucer"
        case .dayDone: "checkmark"
        }
    }
}

/// The hero time: ticking while working or on a break, fixed otherwise.
struct ShiftTimeText: View {
    let snapshot: ShiftSnapshot
    /// Point size, in SF Rounded with tabular digits.
    var size: CGFloat = 28

    var body: some View {
        Group {
            switch snapshot.phase {
            case .working:
                if let since = snapshot.workingSince {
                    Text(timerInterval: since...Date.distantFuture, countsDown: false)
                } else {
                    Text(ShiftClock.clockString(snapshot.workedSeconds))
                }
            case .onBreak:
                if let start = snapshot.breakStart {
                    Text(timerInterval: start...Date.distantFuture, countsDown: false)
                } else {
                    Text("Break")
                }
            case .dayDone:
                Text(ShiftClock.durationString(snapshot.workedSeconds))
            case .offClock:
                Text("0:00")
            }
        }
        .font(.system(size: size, weight: .semibold, design: .rounded).monospacedDigit())
        .contentTransition(.numericText())
    }
}

/// The ticket time: ticking while its timer runs, fixed when paused.
struct TicketTimeText: View {
    let snapshot: ShiftSnapshot
    /// A ticking timer reserves its widest width; this sets where the digits sit in it.
    var alignment: TextAlignment = .leading

    var body: some View {
        Group {
            if let since = snapshot.ticketSince {
                Text(timerInterval: since...Date.distantFuture, countsDown: false)
            } else {
                Text(ShiftClock.clockString(snapshot.ticketSeconds))
            }
        }
        .multilineTextAlignment(alignment)
    }
}
