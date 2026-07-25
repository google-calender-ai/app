import Foundation

struct CalendarEvent: Identifiable, Equatable, Codable {
    var id: String
    var title: String
    var startDate: Date
    var endDate: Date
}
