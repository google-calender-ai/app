import SwiftUI

struct CalendarMonthView: View {
    let calendar: Calendar
    let eventDates: Set<DateComponents>
    @Binding var visibleMonth: Date
    let onSelect: (Date) -> Void

    private static let weekdaySymbols = ["일", "월", "화", "수", "목", "금", "토"]
    private static let swipeThreshold: CGFloat = 50

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                ForEach(Array(Self.weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                    Text(symbol)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(WeekdayColor.color(forWeekday: index + 1))
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 12) {
                ForEach(Array(MonthGrid.cells(for: visibleMonth, calendar: calendar).enumerated()), id: \.offset) { _, date in
                    if let date {
                        dayCell(for: date)
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if value.translation.width <= -Self.swipeThreshold {
                        changeMonth(by: 1)
                    } else if value.translation.width >= Self.swipeThreshold {
                        changeMonth(by: -1)
                    }
                }
        )
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
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isToday ? .white : WeekdayColor.color(forWeekday: weekday))
                    .frame(width: 32, height: 32)
                    .background {
                        if isToday {
                            Circle().fill(Color.red)
                        }
                    }

                Circle()
                    .fill(Color.blue)
                    .frame(width: 4, height: 4)
                    .opacity(hasEvent ? 1 : 0)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
    }

    private func changeMonth(by offset: Int) {
        guard let newMonth = calendar.date(byAdding: .month, value: offset, to: visibleMonth) else { return }
        visibleMonth = newMonth
    }
}
