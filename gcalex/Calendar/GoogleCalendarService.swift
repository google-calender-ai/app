import Foundation

protocol GoogleCalendarServicing {
    func listEvents(from startDate: Date, to endDate: Date) async throws -> [CalendarEvent]
    func createEvent(title: String, startDate: Date, endDate: Date) async throws -> CalendarEvent
    func updateEvent(id: String, title: String, startDate: Date, endDate: Date) async throws -> CalendarEvent
    func deleteEvent(id: String) async throws
}

enum CalendarServiceError: Error, Equatable {
    case requestFailed(statusCode: Int)
    case decodingFailed
}

final class GoogleCalendarService: GoogleCalendarServicing {
    private let tokenProvider: () async throws -> String
    private let httpClient: HTTPClient
    private let baseURL = URL(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
    private let isoFormatter = ISO8601DateFormatter()

    init(tokenProvider: @escaping () async throws -> String, httpClient: HTTPClient = URLSession.shared) {
        self.tokenProvider = tokenProvider
        self.httpClient = httpClient
    }

    func listEvents(from startDate: Date, to endDate: Date) async throws -> [CalendarEvent] {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: isoFormatter.string(from: startDate)),
            URLQueryItem(name: "timeMax", value: isoFormatter.string(from: endDate)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime")
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        let (data, response) = try await send(request)
        try Self.checkStatus(response)
        let decoded = try Self.decode(GoogleEventsResponse.self, from: data)
        return decoded.items.map(Self.toCalendarEvent)
    }

    func createEvent(title: String, startDate: Date, endDate: Date) async throws -> CalendarEvent {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.encode(
            GoogleEventPayload(summary: title, start: .init(dateTime: isoFormatter.string(from: startDate)), end: .init(dateTime: isoFormatter.string(from: endDate)))
        )
        let (data, response) = try await send(request)
        try Self.checkStatus(response)
        let decoded = try Self.decode(GoogleEventItem.self, from: data)
        return Self.toCalendarEvent(decoded)
    }

    func updateEvent(id: String, title: String, startDate: Date, endDate: Date) async throws -> CalendarEvent {
        var request = URLRequest(url: baseURL.appendingPathComponent(id))
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.encode(
            GoogleEventPayload(summary: title, start: .init(dateTime: isoFormatter.string(from: startDate)), end: .init(dateTime: isoFormatter.string(from: endDate)))
        )
        let (data, response) = try await send(request)
        try Self.checkStatus(response)
        let decoded = try Self.decode(GoogleEventItem.self, from: data)
        return Self.toCalendarEvent(decoded)
    }

    func deleteEvent(id: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent(id))
        request.httpMethod = "DELETE"
        let (_, response) = try await send(request)
        try Self.checkStatus(response)
    }

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        var authed = request
        let token = try await tokenProvider()
        authed.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await httpClient.data(for: authed)
    }

    private static func checkStatus(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw CalendarServiceError.requestFailed(statusCode: code)
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw CalendarServiceError.decodingFailed
        }
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }

    private static func toCalendarEvent(_ item: GoogleEventItem) -> CalendarEvent {
        let formatter = ISO8601DateFormatter()
        return CalendarEvent(
            id: item.id,
            title: item.summary,
            startDate: formatter.date(from: item.start.dateTime) ?? Date(),
            endDate: formatter.date(from: item.end.dateTime) ?? Date()
        )
    }
}

private struct GoogleEventsResponse: Decodable {
    let items: [GoogleEventItem]
}

private struct GoogleEventItem: Codable {
    let id: String
    let summary: String
    let start: GoogleEventDateTime
    let end: GoogleEventDateTime
}

private struct GoogleEventDateTime: Codable {
    let dateTime: String
}

private struct GoogleEventPayload: Encodable {
    let summary: String
    let start: GoogleEventDateTime
    let end: GoogleEventDateTime
}
