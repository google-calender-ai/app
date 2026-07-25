import SwiftUI

struct CalendarMonthView: View {
    let calendar: Calendar
    let eventDates: Set<DateComponents>
    let onSelect: (Date) -> Void

    @State private var visibleMonth: Date

    init(calendar: Calendar, eventDates: Set<DateComponents>, onSelect: @escaping (Date) -> Void) {
        self.calendar = calendar
        self.eventDates = eventDates
        self.onSelect = onSelect
        _visibleMonth = State(initialValue: Date())
    }

    private static let weekdaySymbols = ["일", "월", "화", "수", "목", "금", "토"]

    private var monthTitleFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월"
        return formatter
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    changeMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.glass)

                Spacer()
                Text(monthTitleFormatter.string(from: visibleMonth))
                    .font(.headline)
                Spacer()

                Button {
                    changeMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.glass)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .glassEffect(in: RoundedRectangle(cornerRadius: 20))

            HStack {
                ForEach(Array(Self.weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                    Text(symbol)
                        .font(.caption)
                        .foregroundStyle(WeekdayColor.color(forWeekday: index + 1))
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 12) {
                ForEach(Array(MonthGrid.cells(for: visibleMonth, calendar: calendar).enumerated()), id: \.offset) { _, date in
                    if let date {
                        dayCell(for: date)
                    } else {
                        Color.clear.frame(height: 36)
                    }
                }
            }
        }
    }

    private func dayCell(for date: Date) -> some View {
        let weekday = calendar.component(.weekday, from: date)
        let day = calendar.component(.day, from: date)
        let isToday = calendar.isDateInToday(date)
        let hasEvent = eventDates.contains(calendar.dateComponents([.year, .month, .day], from: date))

        return Button {
            onSelect(date)
        } label: {
            VStack(spacing: 4) {
                Text("\(day)")
                    .font(.body)
                    .foregroundStyle(isToday ? .white : WeekdayColor.color(forWeekday: weekday))
                    .frame(width: 32, height: 32)
                    .background {
                        if isToday {
                            Circle().fill(Color.blue)
                        }
                    }

                Circle()
                    .fill(Color.blue)
                    .frame(width: 4, height: 4)
                    .opacity(hasEvent ? 1 : 0)
            }
            .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.plain)
    }

    private func changeMonth(by offset: Int) {
        guard let newMonth = calendar.date(byAdding: .month, value: offset, to: visibleMonth) else { return }
        visibleMonth = newMonth
    }
}
