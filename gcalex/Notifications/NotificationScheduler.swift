import Foundation
import UserNotifications

enum NotificationContentBuilder {
    static func dailyAgendaText(todayEvents: [CalendarEvent], tomorrowEvents: [CalendarEvent]) -> String {
        let today = todayEvents.isEmpty
            ? "오늘 일정 없음"
            : "오늘: " + todayEvents.map(\.title).joined(separator: ", ")
        let tomorrow = tomorrowEvents.isEmpty
            ? "내일 일정 없음"
            : "내일: " + tomorrowEvents.map(\.title).joined(separator: ", ")
        return "\(today)\n\(tomorrow)"
    }
}

final class NotificationScheduler {
    private let center: UNUserNotificationCenter
    private static let identifier = "daily-agenda"

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func scheduleDailyAgenda(at time: DateComponents, todayEvents: [CalendarEvent], tomorrowEvents: [CalendarEvent]) async {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])

        let content = UNMutableNotificationContent()
        content.title = "오늘의 일정"
        content.body = NotificationContentBuilder.dailyAgendaText(todayEvents: todayEvents, tomorrowEvents: tomorrowEvents)
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: time, repeats: true)
        let request = UNNotificationRequest(identifier: Self.identifier, content: content, trigger: trigger)
        try? await center.add(request)
    }
}
