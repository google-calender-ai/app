import Foundation

actor EventStore {
    private(set) var allEvents: [CalendarEvent] = []
    nonisolated private let calendarService: GoogleCalendarServicing

    init(calendarService: GoogleCalendarServicing) {
        self.calendarService = calendarService
    }

    func refresh(from startDate: Date, to endDate: Date) async throws {
        allEvents = try await calendarService.listEvents(from: startDate, to: endDate)
    }

    func events(on date: Date, calendar: Calendar = .current) -> [CalendarEvent] {
        allEvents.filter { calendar.isDate($0.startDate, inSameDayAs: date) }
    }
}
