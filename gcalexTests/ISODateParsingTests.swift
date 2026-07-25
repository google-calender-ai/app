import Testing
import Foundation
@testable import gcalex

struct ISODateParsingTests {
    @Test func combineParsesDateAndTimeInCurrentTimeZone() throws {
        let date = try ISODateParsing.combine(date: "2026-07-28", time: "13:00")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        #expect(components.year == 2026)
        #expect(components.month == 7)
        #expect(components.day == 28)
        #expect(components.hour == 13)
        #expect(components.minute == 0)
    }

    @Test func combineThrowsOnInvalidInput() {
        #expect(throws: ISODateParsingError.invalidFormat(date: "not-a-date", time: "13:00")) {
            try ISODateParsing.combine(date: "not-a-date", time: "13:00")
        }
    }
}
