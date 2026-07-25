import SwiftUI
import UIKit

struct CalendarMonthView: UIViewRepresentable {
    /// Injected so producer (`RootView.refreshMonth` building `eventDates`) and
    /// consumer (this view's `UICalendarView`) share a single calendar — a
    /// mismatch there can make `Set.contains` silently miss a decorated day.
    let calendar: Calendar
    let eventDates: Set<DateComponents>
    let onSelect: (Date) -> Void

    func makeUIView(context: Context) -> UICalendarView {
        let view = UICalendarView()
        view.calendar = calendar
        view.delegate = context.coordinator
        let selection = UICalendarSelectionSingleDate(delegate: context.coordinator)
        view.selectionBehavior = selection
        return view
    }

    func updateUIView(_ uiView: UICalendarView, context: Context) {
        context.coordinator.eventDates = eventDates
        uiView.reloadDecorations(forDateComponents: Array(eventDates), animated: true)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(calendar: calendar, eventDates: eventDates, onSelect: onSelect)
    }

    final class Coordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
        let calendar: Calendar
        var eventDates: Set<DateComponents>
        let onSelect: (Date) -> Void

        init(calendar: Calendar, eventDates: Set<DateComponents>, onSelect: @escaping (Date) -> Void) {
            self.calendar = calendar
            self.eventDates = eventDates
            self.onSelect = onSelect
        }

        func calendarView(_ calendarView: UICalendarView, decorationFor dateComponents: DateComponents) -> UICalendarView.Decoration? {
            // The delegate-provided `dateComponents` can carry extra fields
            // (calendar/era/timeZone) that the stored `eventDates` lack, which
            // would make `Set.contains` spuriously false. Compare only on
            // year/month/day, matching how `eventDates` is built.
            let key = DateComponents(
                year: dateComponents.year,
                month: dateComponents.month,
                day: dateComponents.day
            )
            guard eventDates.contains(key) else { return nil }
            return .default(color: .systemBlue, size: .small)
        }

        func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate dateComponents: DateComponents?) {
            guard let dateComponents, let date = calendar.date(from: dateComponents) else { return }
            onSelect(date)
        }
    }
}
