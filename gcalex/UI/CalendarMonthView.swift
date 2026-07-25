import SwiftUI
import UIKit

struct CalendarMonthView: UIViewRepresentable {
    let eventDates: Set<DateComponents>
    let onSelect: (Date) -> Void

    func makeUIView(context: Context) -> UICalendarView {
        let view = UICalendarView()
        view.calendar = Calendar(identifier: .gregorian)
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
        Coordinator(eventDates: eventDates, onSelect: onSelect)
    }

    final class Coordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
        var eventDates: Set<DateComponents>
        let onSelect: (Date) -> Void

        init(eventDates: Set<DateComponents>, onSelect: @escaping (Date) -> Void) {
            self.eventDates = eventDates
            self.onSelect = onSelect
        }

        func calendarView(_ calendarView: UICalendarView, decorationFor dateComponents: DateComponents) -> UICalendarView.Decoration? {
            guard eventDates.contains(dateComponents) else { return nil }
            return .default(color: .systemBlue, size: .small)
        }

        func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate dateComponents: DateComponents?) {
            guard let dateComponents, let date = Calendar(identifier: .gregorian).date(from: dateComponents) else { return }
            onSelect(date)
        }
    }
}
