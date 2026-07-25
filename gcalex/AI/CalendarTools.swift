import Foundation
import FoundationModels

struct ListEventsTool: Tool {
    let name = "listEvents"
    let description = "Lists calendar events between two ISO 8601 dates (inclusive), used to resolve ambiguous references like a title mentioned without an id."

    @Generable
    struct Arguments {
        @Guide(description: "ISO 8601 start date, e.g. 2026-07-21")
        var startDate: String
        @Guide(description: "ISO 8601 end date, e.g. 2026-07-28")
        var endDate: String
    }

    let eventStore: EventStore

    func call(arguments: Arguments) async throws -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        guard let start = formatter.date(from: arguments.startDate),
              let end = formatter.date(from: arguments.endDate) else {
            return "날짜 형식을 이해하지 못했습니다."
        }
        try await eventStore.refresh(from: start, to: end)
        let events = await eventStore.allEvents
        if events.isEmpty { return "해당 기간에 일정이 없습니다." }
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        timeFormatter.timeZone = .current
        return events.map { event in
            "id: \(event.id), title: \(event.title), start: \(timeFormatter.string(from: event.startDate))"
        }.joined(separator: "\n")
    }
}

struct CreateEventTool: Tool {
    let name = "createEvent"
    let description = "Creates a new calendar event on a specific date and time range. Executes immediately without confirmation."

    @Generable
    struct Arguments {
        var title: String
        @Guide(description: "ISO 8601 date, e.g. 2026-07-28")
        var date: String
        @Guide(description: "24-hour start time, e.g. 13:00")
        var startTime: String
        @Guide(description: "24-hour end time, e.g. 15:00")
        var endTime: String
    }

    let calendarService: GoogleCalendarServicing

    func call(arguments: Arguments) async throws -> String {
        let start = try ISODateParsing.combine(date: arguments.date, time: arguments.startTime)
        let end = try ISODateParsing.combine(date: arguments.date, time: arguments.endTime)
        let created = try await calendarService.createEvent(title: arguments.title, startDate: start, endDate: end)
        return "생성 완료: \(created.title) (\(arguments.date) \(arguments.startTime)~\(arguments.endTime))"
    }
}

struct UpdateEventTool: Tool {
    let name = "updateEvent"
    let description = "Updates an existing event's title, date, or time range. Always call listEvents first to find the eventId. Requires user confirmation before it takes effect."

    @Generable
    struct Arguments {
        @Guide(description: "The id of the event to update, obtained from a prior listEvents call")
        var eventId: String
        var title: String
        @Guide(description: "ISO 8601 date, e.g. 2026-07-28")
        var date: String
        @Guide(description: "24-hour start time, e.g. 13:00")
        var startTime: String
        @Guide(description: "24-hour end time, e.g. 15:00")
        var endTime: String
    }

    let calendarService: GoogleCalendarServicing
    let confirmationCenter: ConfirmationCenter

    func call(arguments: Arguments) async throws -> String {
        let approved = await confirmationCenter.requestConfirmation(
            message: "'\(arguments.title)' 일정을 \(arguments.date) \(arguments.startTime)~\(arguments.endTime)(으)로 수정할까요?"
        )
        guard approved else { return "사용자가 수정을 취소했습니다." }
        let start = try ISODateParsing.combine(date: arguments.date, time: arguments.startTime)
        let end = try ISODateParsing.combine(date: arguments.date, time: arguments.endTime)
        let updated = try await calendarService.updateEvent(id: arguments.eventId, title: arguments.title, startDate: start, endDate: end)
        return "수정 완료: \(updated.title)"
    }
}

struct DeleteEventTool: Tool {
    let name = "deleteEvent"
    let description = "Deletes an existing event. Always call listEvents first to find the eventId. Requires user confirmation before it takes effect."

    @Generable
    struct Arguments {
        @Guide(description: "The id of the event to delete, obtained from a prior listEvents call")
        var eventId: String
        @Guide(description: "The event's title, shown to the user in the confirmation prompt")
        var eventTitle: String
    }

    let calendarService: GoogleCalendarServicing
    let confirmationCenter: ConfirmationCenter

    func call(arguments: Arguments) async throws -> String {
        let approved = await confirmationCenter.requestConfirmation(
            message: "'\(arguments.eventTitle)' 일정을 삭제할까요?"
        )
        guard approved else { return "사용자가 삭제를 취소했습니다." }
        try await calendarService.deleteEvent(id: arguments.eventId)
        return "삭제 완료: \(arguments.eventTitle)"
    }
}
