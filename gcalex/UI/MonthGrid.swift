import Foundation

/// Produces the ordered list of dates (with `nil` placeholders for
/// out-of-month blanks) to render in a 7-column month grid, so the first
/// real day of the month lands under its correct weekday column and the
/// final row is padded out to a full week.
enum MonthGrid {
    static func cells(for referenceDate: Date, calendar: Calendar) -> [Date?] {
        let monthInterval = calendar.dateInterval(of: .month, for: referenceDate)!
        let firstOfMonth = monthInterval.start
        let daysInMonth = calendar.range(of: .day, in: .month, for: referenceDate)!.count
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let leadingBlanks = firstWeekday - 1

        var cells: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for dayOffset in 0..<daysInMonth {
            cells.append(calendar.date(byAdding: .day, value: dayOffset, to: firstOfMonth))
        }

        let trailingBlanks = (7 - cells.count % 7) % 7
        cells.append(contentsOf: Array(repeating: nil, count: trailingBlanks))
        return cells
    }
}
