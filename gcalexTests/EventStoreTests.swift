import Testing
import Foundation
@testable import gcalex

final class StubCalendarService: GoogleCalendarServicing, @unchecked Sendable {
    var eventsToReturn: [CalendarEvent] = []
    private(set) var lastRange: (from: Date, to: Date)?

    func listEvents(from startDate: Date, to endDate: Date) async throws -> [CalendarEvent] {
        lastRange = (startDate, endDate)
        return eventsToReturn
    }

    func createEvent(title: String, startDate: Date, endDate: Date) async throws -> CalendarEvent {
        CalendarEvent(id: "stub", title: title, startDate: startDate, endDate: endDate)
    }

    func updateEvent(id: String, title: String, startDate: Date, endDate: Date) async throws -> CalendarEvent {
        CalendarEvent(id: id, title: title, startDate: startDate, endDate: endDate)
    }

    func deleteEvent(id: String) async throws {}
}

struct EventStoreTests {
    @Test func refreshPopulatesAllEvents() async throws {
        let stub = StubCalendarService()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let day1 = calendar.date(from: DateComponents(year: 2026, month: 7, day: 25, hour: 10))!
        stub.eventsToReturn = [CalendarEvent(id: "1", title: "치과", startDate: day1, endDate: day1.addingTimeInterval(3600))]

        let store = EventStore(calendarService: stub)
        try await store.refresh(from: day1, to: day1)

        let all = await store.allEvents
        #expect(all.count == 1)
        #expect(all.first?.title == "치과")
    }

    @Test func eventsOnFiltersByCalendarDay() async throws {
        let stub = StubCalendarService()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let day1 = calendar.date(from: DateComponents(year: 2026, month: 7, day: 25, hour: 10))!
        let day2 = calendar.date(from: DateComponents(year: 2026, month: 7, day: 26, hour: 9))!
        stub.eventsToReturn = [
            CalendarEvent(id: "1", title: "치과", startDate: day1, endDate: day1.addingTimeInterval(3600)),
            CalendarEvent(id: "2", title: "회의", startDate: day2, endDate: day2.addingTimeInterval(3600))
        ]

        let store = EventStore(calendarService: stub)
        try await store.refresh(from: day1, to: day2)

        let onDay1 = await store.events(on: day1, calendar: calendar)
        #expect(onDay1.map(\.id) == ["1"])
    }
}
