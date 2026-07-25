import Testing
import SwiftUI
@testable import gcalex

struct WeekdayColorTests {
    @Test func sundayIsRed() {
        #expect(WeekdayColor.color(forWeekday: 1) == .red)
    }

    @Test func saturdayIsBlue() {
        #expect(WeekdayColor.color(forWeekday: 7) == .blue)
    }

    @Test func weekdaysArePrimary() {
        for weekday in 2...6 {
            #expect(WeekdayColor.color(forWeekday: weekday) == .primary)
        }
    }
}
