import SwiftUI

/// Maps a `Calendar`-style 1-based weekday (Sunday = 1 ... Saturday = 7) to
/// the color it should render in, both for the weekday header letter and the
/// date number itself.
enum WeekdayColor {
    static func color(forWeekday weekday: Int) -> Color {
        switch weekday {
        case 1: return .red
        case 7: return .blue
        default: return .primary
        }
    }
}
