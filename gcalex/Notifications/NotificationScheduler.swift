import Foundation
// `UserNotifications` is an unaudited ObjC framework (`UNUserNotificationCenter`
// carries no Sendable annotation in the SDK header). `@preconcurrency` is
// the sanctioned way to interop with such a module when asserting our own
// type's Sendable conformance below — it downgrades Sendable-related
// diagnostics about `UNUserNotificationCenter` at this framework boundary
// instead of forcing an `@unchecked` escape hatch on `NotificationScheduler`
// itself.
@preconcurrency import UserNotifications

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

/// Genuinely `Sendable` (not `@unchecked`): its only stored property,
/// `center`, is an immutable `let` of `UNUserNotificationCenter` — a
/// framework singleton accessor whose documented usage pattern (call its
/// methods from any context) is exactly what `@preconcurrency import
/// UserNotifications` above lets the compiler accept for this
/// conformance, since the framework itself predates Sendable auditing.
final class NotificationScheduler: Sendable {
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
