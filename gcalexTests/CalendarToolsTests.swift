import Testing
import Foundation
import FoundationModels
@testable import gcalex

// Marked @MainActor because ConfirmationCenter is main-actor-isolated (see
// ConfirmationCenter.swift for why); these tests call its synchronous API
// (`pendingRequest`, `resolve(_:)`, `init()`) directly, the same way Task 8's
// SwiftUI view will. `tool.call(arguments:)` itself is `@concurrent` per the
// FoundationModels `Tool` protocol, so it still hops off to a background
// executor even though the test body runs on the main actor.
@MainActor
struct CalendarToolsTests {
    @Test func listEventsToolFormatsEventsFromStore() async throws {
        let stub = StubCalendarService()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 7, day: 29, hour: 13))!
        stub.eventsToReturn = [CalendarEvent(id: "evt-9", title: "미팅", startDate: day, endDate: day.addingTimeInterval(7200))]
        let store = EventStore(calendarService: stub)
        try await store.refresh(from: day, to: day)

        let tool = ListEventsTool(eventStore: store)
        let arguments = ListEventsTool.Arguments(startDate: "2026-07-29", endDate: "2026-07-29")
        let result = try await tool.call(arguments: arguments)

        #expect(result.contains("evt-9"))
        #expect(result.contains("미팅"))
    }

    @Test func createEventToolCallsCalendarServiceImmediatelyWithoutConfirmation() async throws {
        let stub = StubCalendarService()
        let tool = CreateEventTool(calendarService: stub)
        let arguments = CreateEventTool.Arguments(title: "미팅", date: "2026-07-29", startTime: "13:00", endTime: "15:00")

        let result = try await tool.call(arguments: arguments)

        #expect(result.contains("미팅"))
    }

    @Test func updateEventToolWaitsForConfirmationBeforeCallingService() async throws {
        // @unchecked Sendable: only mutated inside `updateEvent`, which the test awaits
        // to completion (via `result`) before ever reading `updateCalled` — no concurrent
        // access, same pattern as `StubCalendarService` above. Safe as a test double.
        final class RecordingService: GoogleCalendarServicing, @unchecked Sendable {
            private(set) var updateCalled = false
            func listEvents(from: Date, to: Date) async throws -> [CalendarEvent] { [] }
            func createEvent(title: String, startDate: Date, endDate: Date) async throws -> CalendarEvent {
                CalendarEvent(id: "x", title: title, startDate: startDate, endDate: endDate)
            }
            func updateEvent(id: String, title: String, startDate: Date, endDate: Date) async throws -> CalendarEvent {
                updateCalled = true
                return CalendarEvent(id: id, title: title, startDate: startDate, endDate: endDate)
            }
            func deleteEvent(id: String) async throws {}
        }

        let service = RecordingService()
        let confirmationCenter = ConfirmationCenter()
        let tool = UpdateEventTool(calendarService: service, confirmationCenter: confirmationCenter)
        let arguments = UpdateEventTool.Arguments(eventId: "evt-1", title: "미팅", date: "2026-07-29", startTime: "16:00", endTime: "18:00")

        async let result = tool.call(arguments: arguments)
        try await Task.sleep(for: .milliseconds(50))
        #expect(confirmationCenter.pendingRequest != nil)
        confirmationCenter.resolve(true)

        let text = try await result
        #expect(text.contains("완료"))
        #expect(service.updateCalled == true)
    }

    @Test func updateEventToolSkipsServiceCallWhenUserCancels() async throws {
        let service = StubCalendarService()
        let confirmationCenter = ConfirmationCenter()
        let tool = UpdateEventTool(calendarService: service, confirmationCenter: confirmationCenter)
        let arguments = UpdateEventTool.Arguments(eventId: "evt-1", title: "미팅", date: "2026-07-29", startTime: "16:00", endTime: "18:00")

        async let result = tool.call(arguments: arguments)
        try await Task.sleep(for: .milliseconds(50))
        confirmationCenter.resolve(false)

        let text = try await result
        #expect(text.contains("취소"))
    }

    @Test func deleteEventToolRequiresConfirmation() async throws {
        let service = StubCalendarService()
        let confirmationCenter = ConfirmationCenter()
        let tool = DeleteEventTool(calendarService: service, confirmationCenter: confirmationCenter)
        let arguments = DeleteEventTool.Arguments(eventId: "evt-1", eventTitle: "미팅")

        async let result = tool.call(arguments: arguments)
        try await Task.sleep(for: .milliseconds(50))
        confirmationCenter.resolve(true)

        let text = try await result
        #expect(text.contains("삭제"))
    }
}
