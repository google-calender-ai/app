import Testing
import Foundation
@testable import gcalex

struct NotificationSchedulerTests {
    @Test func dailyAgendaTextListsBothDays() {
        let today = CalendarEvent(id: "1", title: "치과", startDate: Date(), endDate: Date())
        let tomorrow = CalendarEvent(id: "2", title: "회의", startDate: Date(), endDate: Date())

        let text = NotificationContentBuilder.dailyAgendaText(todayEvents: [today], tomorrowEvents: [tomorrow])

        #expect(text.contains("치과"))
        #expect(text.contains("회의"))
    }

    @Test func dailyAgendaTextHandlesEmptyDays() {
        let text = NotificationContentBuilder.dailyAgendaText(todayEvents: [], tomorrowEvents: [])

        #expect(text.contains("오늘 일정 없음"))
        #expect(text.contains("내일 일정 없음"))
    }
}
