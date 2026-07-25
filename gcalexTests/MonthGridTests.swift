import Testing
import Foundation
@testable import gcalex

struct MonthGridTests {
    @Test func julyTwoThousandTwentySixHasThreeLeadingBlanksAndOneTrailingBlank() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 7, day: 15))!

        let cells = MonthGrid.cells(for: referenceDate, calendar: calendar)

        // 2026-07-01 is a Wednesday (weekday 4), so 3 leading blanks precede it.
        #expect(cells[0] == nil)
        #expect(cells[1] == nil)
        #expect(cells[2] == nil)
        let firstDay = cells[3]
        #expect(firstDay != nil)
        #expect(calendar.component(.day, from: firstDay!) == 1)

        // 31 real days + 3 leading blanks = 34; padded to a multiple of 7 = 35, so 1 trailing blank.
        #expect(cells.count == 35)
        #expect(cells.last! == nil)
    }

    @Test func everyNonNilCellFallsWithinTheReferenceMonthInOrder() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 7, day: 1))!

        let cells = MonthGrid.cells(for: referenceDate, calendar: calendar)
        let daysPresent = cells.compactMap { $0 }.map { calendar.component(.day, from: $0) }

        #expect(daysPresent == Array(1...31))
    }
}
