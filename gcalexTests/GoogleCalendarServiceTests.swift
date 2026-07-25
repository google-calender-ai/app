import Testing
import Foundation
@testable import gcalex

// @unchecked Sendable: configured synchronously before use, never mutated concurrently — safe as a test double.
final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    var nextData: Data = Data()
    var nextStatusCode: Int = 200
    private(set) var lastRequest: URLRequest?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: nextStatusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (nextData, response)
    }
}

struct GoogleCalendarServiceTests {
    @Test func listEventsParsesGoogleEventsResponse() async throws {
        let mock = MockHTTPClient()
        mock.nextData = """
        {
          "items": [
            {
              "id": "evt1",
              "summary": "치과",
              "start": { "dateTime": "2026-07-25T10:00:00+09:00" },
              "end": { "dateTime": "2026-07-25T11:00:00+09:00" }
            }
          ]
        }
        """.data(using: .utf8)!

        let service = GoogleCalendarService(
            tokenProvider: { "fake-token" },
            httpClient: mock
        )

        let events = try await service.listEvents(
            from: Date(timeIntervalSince1970: 0),
            to: Date(timeIntervalSince1970: 1_000_000)
        )

        #expect(events == [
            CalendarEvent(
                id: "evt1",
                title: "치과",
                startDate: ISO8601DateFormatter().date(from: "2026-07-25T10:00:00+09:00")!,
                endDate: ISO8601DateFormatter().date(from: "2026-07-25T11:00:00+09:00")!
            )
        ])
        #expect(mock.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer fake-token")
    }

    @Test func createEventSendsPostAndParsesResponse() async throws {
        let mock = MockHTTPClient()
        mock.nextData = """
        {
          "id": "new1",
          "summary": "미팅",
          "start": { "dateTime": "2026-07-28T13:00:00+09:00" },
          "end": { "dateTime": "2026-07-28T15:00:00+09:00" }
        }
        """.data(using: .utf8)!

        let service = GoogleCalendarService(tokenProvider: { "t" }, httpClient: mock)
        let event = try await service.createEvent(
            title: "미팅",
            startDate: ISO8601DateFormatter().date(from: "2026-07-28T13:00:00+09:00")!,
            endDate: ISO8601DateFormatter().date(from: "2026-07-28T15:00:00+09:00")!
        )

        #expect(event.id == "new1")
        #expect(mock.lastRequest?.httpMethod == "POST")
    }

    @Test func requestFailureThrowsWithStatusCode() async throws {
        let mock = MockHTTPClient()
        mock.nextStatusCode = 401
        mock.nextData = Data()
        let service = GoogleCalendarService(tokenProvider: { "t" }, httpClient: mock)

        await #expect(throws: CalendarServiceError.requestFailed(statusCode: 401)) {
            _ = try await service.listEvents(from: Date(), to: Date())
        }
    }

    @Test func deleteEventSendsDeleteToCorrectPath() async throws {
        let mock = MockHTTPClient()
        mock.nextStatusCode = 204
        let service = GoogleCalendarService(tokenProvider: { "t" }, httpClient: mock)
        try await service.deleteEvent(id: "evt1")

        #expect(mock.lastRequest?.httpMethod == "DELETE")
        #expect(mock.lastRequest?.url?.absoluteString.hasSuffix("/evt1") == true)
    }

    @Test func listEventsHandlesAllDayEventsWithoutThrowing() async throws {
        let mock = MockHTTPClient()
        mock.nextData = """
        {
          "items": [
            {
              "id": "evt-holiday",
              "summary": "공휴일",
              "start": { "date": "2026-07-25" },
              "end": { "date": "2026-07-26" }
            }
          ]
        }
        """.data(using: .utf8)!

        let service = GoogleCalendarService(tokenProvider: { "t" }, httpClient: mock)
        let events = try await service.listEvents(from: Date(), to: Date())

        #expect(events.first?.id == "evt-holiday")
        #expect(events.first?.title == "공휴일")
    }
}
