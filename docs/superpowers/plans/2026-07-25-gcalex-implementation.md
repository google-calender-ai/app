# gcalex Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a personal iOS app that syncs Google Calendar, sends a daily local
notification summarizing today's/tomorrow's schedule, and lets the user create,
edit, delete, and query events through a chat interface powered by Apple's
on-device Foundation Models.

**Architecture:** SwiftUI app, no server. `GoogleCalendarService` talks to the
Calendar API v3 over `URLSession`. `AuthService` wraps Google Sign-In for iOS.
Four `Tool`-conforming structs (list/create/update/delete) expose the calendar
to a `LanguageModelSession` (Foundation Models); `ChatEngine` drives the
session and a `ConfirmationCenter` gates destructive tool calls on user
approval before they touch the network. `NotificationScheduler` turns cached
events into a daily local notification, refreshed via `BGTaskScheduler`.

**Tech Stack:** Swift 6, SwiftUI, Foundation Models framework, Google Sign-In
for iOS (SPM), Swift Testing (`import Testing`), xcodegen for project
generation, `xcodebuild` for build/test from the CLI.

## Global Constraints

- Deployment target: iOS 26.0, iPhone 15 Pro or later (A17 Pro+, Apple
  Intelligence compatible) — from spec section 2.
- No backend server; no cloud AI fallback — AI parsing is 100% on-device via
  Foundation Models — from spec sections 2 and 10.
- Single user, no multi-account / multi-tenant support — from spec section 2.
- Only one Google calendar (`primary`) is read/written — no calendar picker —
  from spec section 10.
- No recurring-event (RRULE) creation — multi-date input becomes N individual
  events — from spec section 6.
- All user-facing chat/notification copy is Korean, polite register (존댓말) —
  from spec sections 6 and 7.
- `updateEvent` and `deleteEvent` must always be gated behind an explicit user
  confirmation before the network call executes; `createEvent` executes
  immediately — from spec sections 3 and 7.
- Google OAuth credentials must persist across launches via Keychain-backed
  storage and be wiped on sign-out — from spec section 8. (Satisfied by
  Google Sign-In's built-in Keychain-backed session store — see Task 3.)
- Daily notification fires even when both today and tomorrow have zero events
  ("오늘 일정 없음") — from spec section 5.

---

## Task 1: Project scaffold, Google Cloud OAuth client, and smoke build

**Files:**
- Create: `project.yml`
- Create: `gcalex/App/GcalexApp.swift`
- Create: `gcalex/App/ContentView.swift`
- Create: `gcalex/Resources/Info.plist`
- Create: `gcalexTests/SmokeTests.swift`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: an Xcode project (`gcalex.xcodeproj`, generated — not hand-edited)
  with an app target `gcalex` and a test target `gcalexTests`, both buildable
  via `xcodebuild`. A bundle identifier that later tasks and the Google Cloud
  OAuth client must agree on: `com.gsw226.gcalex`.

### Manual prerequisite (cannot be scripted — do this first)

1. Install xcodegen if not present: `brew install xcodegen`.
2. In the [Google Cloud Console](https://console.cloud.google.com/), create a
   new project (e.g. "gcalex").
3. Enable the **Google Calendar API** for that project (APIs & Services →
   Library → search "Google Calendar API" → Enable).
4. Configure the **OAuth consent screen**: User type "External", publishing
   status can stay "Testing" (personal use, your own Google account is the
   only test user needed). Add scope `.../auth/calendar`.
5. Create an **OAuth Client ID** of type "iOS". Bundle ID:
   `com.gsw226.gcalex`. Note the generated **Client ID**
   (`XXXX.apps.googleusercontent.com`) and its **reversed form**
   (`com.googleusercontent.apps.XXXX`) — you'll need both in Step 1 below.
   Substitute the plain Client ID into the `GIDClientID` placeholder (the
   GoogleSignIn SDK auto-reads it from Info.plist to build its active
   configuration), and the reversed form into the `CFBundleURLTypes` URL
   scheme placeholder (which only registers the OAuth redirect scheme, not
   the client ID).

- [ ] **Step 1: Write `project.yml`**

```yaml
name: gcalex
options:
  bundleIdPrefix: com.gsw226
  deploymentTarget:
    iOS: "26.0"
packages:
  GoogleSignIn:
    url: https://github.com/google/GoogleSignIn-iOS
    from: 8.0.0
targets:
  gcalex:
    type: application
    platform: iOS
    sources: [gcalex]
    info:
      path: gcalex/Resources/Info.plist
      properties:
        UILaunchScreen: {}
        GIDClientID: "GIDCLIENTID-PLACEHOLDER-REPLACE-ME.apps.googleusercontent.com"
        CFBundleURLTypes:
          - CFBundleURLSchemes:
              - "REVERSED_CLIENT_ID_PLACEHOLDER"
        BGTaskSchedulerPermittedIdentifiers:
          - "com.gsw226.gcalex.refresh"
        UIBackgroundModes:
          - fetch
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.gsw226.gcalex
        SWIFT_VERSION: "6.0"
        IPHONEOS_DEPLOYMENT_TARGET: "26.0"
    dependencies:
      - package: GoogleSignIn
        product: GoogleSignIn
  gcalexTests:
    type: bundle.unit-test
    platform: iOS
    sources: [gcalexTests]
    settings:
      base:
        SWIFT_VERSION: "6.0"
    dependencies:
      - target: gcalex
```

Replace `REVERSED_CLIENT_ID_PLACEHOLDER` with the reversed client ID you
noted in the manual prerequisite (e.g.
`com.googleusercontent.apps.123456-abc`), and
`GIDCLIENTID-PLACEHOLDER-REPLACE-ME.apps.googleusercontent.com` with the
plain (non-reversed) Client ID (e.g. `123456-abc.apps.googleusercontent.com`).
Both are one-time literal substitutions, not code placeholders — the values
come from your own Google Cloud project and cannot be known ahead of time.
The GoogleSignIn SDK reads `GIDClientID` from Info.plist on first use to
build its active configuration, so no `GIDConfiguration` is set in code.

- [ ] **Step 2: Write `gcalex/Resources/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>ko</string>
  <key>NSUserNotificationsUsageDescription</key>
  <string>오늘과 내일의 일정을 매일 알려드리기 위해 알림 권한이 필요합니다.</string>
</dict>
</plist>
```

- [ ] **Step 3: Write `gcalex/App/ContentView.swift`**

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("gcalex")
            .font(.largeTitle)
    }
}

#Preview {
    ContentView()
}
```

- [ ] **Step 4: Write `gcalex/App/GcalexApp.swift`**

```swift
import SwiftUI
import GoogleSignIn

@main
struct GcalexApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
```

- [ ] **Step 5: Write the smoke test `gcalexTests/SmokeTests.swift`**

```swift
import Testing
@testable import gcalex

struct SmokeTests {
    @Test func contentViewInstantiates() {
        _ = ContentView()
    }
}
```

This test only exists to prove the test target compiles and links against
the app target — later tasks replace it with real coverage. It deliberately
has no `#expect` assertion rather than a tautological one: a passing
instantiation with no thrown error is the entire signal this test is meant
to carry, and dressing that up as a fake assertion would be worse, not
better. Later tasks add tests alongside it rather than depending on it.

- [ ] **Step 6: Generate the Xcode project and build**

```bash
xcodegen generate
xcodebuild -project gcalex.xcodeproj -scheme gcalex -destination 'generic/platform=iOS Simulator' build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Run the smoke test**

```bash
xcodebuild -project gcalex.xcodeproj -scheme gcalex -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Expected: `Test Suite 'All tests' passed` including `SmokeTests`.

- [ ] **Step 8: Add a `.gitignore` and commit**

```bash
cat > .gitignore <<'EOF'
gcalex.xcodeproj/
.build/
DerivedData/
EOF
git add project.yml gcalex gcalexTests .gitignore
git commit -m "feat: scaffold gcalex iOS app via xcodegen"
```

---

## Task 2: CalendarEvent model and GoogleCalendarService (REST client)

**Files:**
- Create: `gcalex/Networking/HTTPClient.swift`
- Create: `gcalex/Calendar/CalendarEvent.swift`
- Create: `gcalex/Calendar/GoogleCalendarService.swift`
- Test: `gcalexTests/GoogleCalendarServiceTests.swift`

**Interfaces:**
- Consumes: nothing external yet (uses a fake `HTTPClient` in tests).
- Produces:
  - `struct CalendarEvent: Identifiable, Equatable, Codable { var id: String;
    var title: String; var startDate: Date; var endDate: Date }` — later
    tasks (EventStore, Tools, NotificationScheduler, UI) all consume this type.
  - `protocol GoogleCalendarServicing { func listEvents(from: Date, to: Date)
    async throws -> [CalendarEvent]; func createEvent(title: String, startDate:
    Date, endDate: Date) async throws -> CalendarEvent; func updateEvent(id:
    String, title: String, startDate: Date, endDate: Date) async throws ->
    CalendarEvent; func deleteEvent(id: String) async throws }`.
  - `final class GoogleCalendarService: GoogleCalendarServicing`, initialized
    as `GoogleCalendarService(tokenProvider: @escaping () async throws ->
    String, httpClient: HTTPClient = URLSession.shared)`.
  - `enum CalendarServiceError: Error, Equatable { case requestFailed(statusCode:
    Int); case decodingFailed }`.

- [ ] **Step 1: Write `HTTPClient.swift`**

```swift
import Foundation

protocol HTTPClient {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPClient {}
```

- [ ] **Step 2: Write `CalendarEvent.swift`**

```swift
import Foundation

struct CalendarEvent: Identifiable, Equatable, Codable {
    var id: String
    var title: String
    var startDate: Date
    var endDate: Date
}
```

- [ ] **Step 3: Write the failing test for `listEvents`**

```swift
import Testing
import Foundation
@testable import gcalex

final class MockHTTPClient: HTTPClient {
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
}
```

- [ ] **Step 4: Run the test to see it fail**

```bash
xcodebuild -project gcalex.xcodeproj -scheme gcalex -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:gcalexTests/GoogleCalendarServiceTests
```

Expected: FAIL — `GoogleCalendarService` does not exist yet.

- [ ] **Step 5: Implement `GoogleCalendarService.swift`**

```swift
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
```

Note: `GoogleEventItem.id` is only known after the server assigns it on
create, so `createEvent`'s response decode (which reads `id` from the POST
response body) is what supplies it — no client-side ID generation happens
anywhere in this service.

- [ ] **Step 6: Run the test to see it pass**

```bash
xcodebuild -project gcalex.xcodeproj -scheme gcalex -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:gcalexTests/GoogleCalendarServiceTests
```

Expected: PASS.

- [ ] **Step 7: Add tests for create/update/delete and error status codes**

```swift
extension GoogleCalendarServiceTests {
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
}
```

- [ ] **Step 8: Run full test file, confirm all pass, then commit**

```bash
xcodebuild -project gcalex.xcodeproj -scheme gcalex -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:gcalexTests/GoogleCalendarServiceTests
git add gcalex/Networking gcalex/Calendar gcalexTests/GoogleCalendarServiceTests.swift
git commit -m "feat: add GoogleCalendarService REST client with CRUD event support"
```

---

## Task 3: AuthService (Google Sign-In wrapper)

**Files:**
- Create: `gcalex/Auth/AuthService.swift`

**Interfaces:**
- Consumes: `GoogleCalendarServicing`'s `tokenProvider` closure shape from
  Task 2 (`() async throws -> String`) — `AuthService.accessToken` is bound
  to fill that role directly.
- Produces: `protocol AuthServicing: AnyObject { var isSignedIn: Bool { get };
  func restorePreviousSignIn() async; func signIn(presentingViewController:
  UIViewController) async throws; func signOut(); func accessToken() async
  throws -> String }` and `final class GoogleAuthService: AuthServicing`.
  Task 11 (Settings + app wiring) consumes this directly.

This task has no meaningful unit-test surface — it is a thin wrapper around
the Google Sign-In SDK, whose behavior (presenting a system auth sheet,
persisting the session in its own Keychain-backed store) can't be exercised
in a simulator test target. It is verified manually in Task 11's app smoke
test. This satisfies spec section 8's Keychain requirement via Google
Sign-In's own session persistence — no custom Keychain code is needed.

- [ ] **Step 1: Write `AuthService.swift`**

```swift
import Foundation
import UIKit
import GoogleSignIn

protocol AuthServicing: AnyObject {
    var isSignedIn: Bool { get }
    func restorePreviousSignIn() async
    func signIn(presentingViewController: UIViewController) async throws
    func signOut()
    func accessToken() async throws -> String
}

enum AuthError: Error, Equatable {
    case notSignedIn
}

final class GoogleAuthService: AuthServicing {
    static let calendarScope = "https://www.googleapis.com/auth/calendar"

    var isSignedIn: Bool {
        GIDSignIn.sharedInstance.currentUser != nil
    }

    func restorePreviousSignIn() async {
        _ = try? await GIDSignIn.sharedInstance.restorePreviousSignIn()
    }

    func signIn(presentingViewController: UIViewController) async throws {
        _ = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: presentingViewController,
            hint: nil,
            additionalScopes: [Self.calendarScope]
        )
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
    }

    func accessToken() async throws -> String {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            throw AuthError.notSignedIn
        }
        try await user.refreshTokensIfNeeded()
        return user.accessToken.tokenString
    }
}
```

- [ ] **Step 2: Build to confirm it compiles against the GoogleSignIn package**

```bash
xcodebuild -project gcalex.xcodeproj -scheme gcalex -destination 'generic/platform=iOS Simulator' build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add gcalex/Auth
git commit -m "feat: add GoogleAuthService wrapping Google Sign-In"
```

---

## Task 4: EventStore (local cache actor)

**Files:**
- Create: `gcalex/Calendar/EventStore.swift`
- Test: `gcalexTests/EventStoreTests.swift`

**Interfaces:**
- Consumes: `GoogleCalendarServicing` and `CalendarEvent` from Task 2.
- Produces: `actor EventStore { init(calendarService: GoogleCalendarServicing);
  func refresh(from: Date, to: Date) async throws; func events(on date: Date,
  calendar: Calendar = .current) -> [CalendarEvent]; var allEvents: [CalendarEvent]
  { get } }`. Consumed by Task 5 (`ListEventsTool`), Task 8/9 (UI), Task 9/10
  (NotificationScheduler).

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import gcalex

final class StubCalendarService: GoogleCalendarServicing {
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
```

- [ ] **Step 2: Run to see it fail**

```bash
xcodebuild -project gcalex.xcodeproj -scheme gcalex -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:gcalexTests/EventStoreTests
```

Expected: FAIL — `EventStore` does not exist.

- [ ] **Step 3: Implement `EventStore.swift`**

```swift
import Foundation

actor EventStore {
    private(set) var allEvents: [CalendarEvent] = []
    private let calendarService: GoogleCalendarServicing

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
```

- [ ] **Step 4: Run to see it pass, then commit**

```bash
xcodebuild -project gcalex.xcodeproj -scheme gcalex -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:gcalexTests/EventStoreTests
git add gcalex/Calendar/EventStore.swift gcalexTests/EventStoreTests.swift
git commit -m "feat: add EventStore local cache actor"
```

---

## Task 5: ConfirmationCenter and Foundation Models calendar Tools

**Files:**
- Create: `gcalex/AI/ISODateParsing.swift`
- Create: `gcalex/AI/ConfirmationCenter.swift`
- Create: `gcalex/AI/CalendarTools.swift`
- Test: `gcalexTests/ISODateParsingTests.swift`
- Test: `gcalexTests/CalendarToolsTests.swift`

**Interfaces:**
- Consumes: `EventStore` (Task 4), `GoogleCalendarServicing` (Task 2).
- Produces:
  - `enum ISODateParsing { static func combine(date: String, time: String)
    throws -> Date }` and `enum ISODateParsingError: Error, Equatable { case
    invalidFormat(date: String, time: String) }`.
  - `@Observable final class ConfirmationCenter { private(set) var
    pendingRequest: ConfirmationRequest?; func requestConfirmation(message:
    String) async -> Bool; func resolve(_ approved: Bool) }` and `struct
    ConfirmationRequest: Identifiable { let id: UUID; let message: String }`.
    Task 8 (DayDetailSheet UI) observes `pendingRequest` to render the
    confirmation card.
  - `struct ListEventsTool: Tool`, `struct CreateEventTool: Tool`, `struct
    UpdateEventTool: Tool`, `struct DeleteEventTool: Tool` (all in
    `CalendarTools.swift`) — consumed by Task 6 (`ChatEngine`).

- [ ] **Step 1: Write the failing test for `ISODateParsing`**

```swift
import Testing
import Foundation
@testable import gcalex

struct ISODateParsingTests {
    @Test func combineParsesDateAndTimeInCurrentTimeZone() throws {
        let date = try ISODateParsing.combine(date: "2026-07-28", time: "13:00")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        #expect(components.year == 2026)
        #expect(components.month == 7)
        #expect(components.day == 28)
        #expect(components.hour == 13)
        #expect(components.minute == 0)
    }

    @Test func combineThrowsOnInvalidInput() {
        #expect(throws: ISODateParsingError.invalidFormat(date: "not-a-date", time: "13:00")) {
            try ISODateParsing.combine(date: "not-a-date", time: "13:00")
        }
    }
}
```

- [ ] **Step 2: Run to see it fail, then implement `ISODateParsing.swift`**

```swift
import Foundation

enum ISODateParsingError: Error, Equatable {
    case invalidFormat(date: String, time: String)
}

enum ISODateParsing {
    static func combine(date: String, time: String) throws -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let result = formatter.date(from: "\(date) \(time)") else {
            throw ISODateParsingError.invalidFormat(date: date, time: time)
        }
        return result
    }
}
```

- [ ] **Step 3: Run to see it pass**

```bash
xcodebuild -project gcalex.xcodeproj -scheme gcalex -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:gcalexTests/ISODateParsingTests
```

Expected: PASS.

- [ ] **Step 4: Write `ConfirmationCenter.swift`**

```swift
import Foundation
import Observation

struct ConfirmationRequest: Identifiable {
    let id = UUID()
    let message: String
}

@Observable
final class ConfirmationCenter {
    private(set) var pendingRequest: ConfirmationRequest?
    private var continuation: CheckedContinuation<Bool, Never>?

    func requestConfirmation(message: String) async -> Bool {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.pendingRequest = ConfirmationRequest(message: message)
        }
    }

    func resolve(_ approved: Bool) {
        pendingRequest = nil
        continuation?.resume(returning: approved)
        continuation = nil
    }
}
```

- [ ] **Step 5: Write the failing tests for the four Tools**

```swift
import Testing
import Foundation
import FoundationModels
@testable import gcalex

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
        final class RecordingService: GoogleCalendarServicing {
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
```

- [ ] **Step 6: Run to see it fail**

```bash
xcodebuild -project gcalex.xcodeproj -scheme gcalex -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:gcalexTests/CalendarToolsTests
```

Expected: FAIL — the four Tool types don't exist yet.

- [ ] **Step 7: Implement `CalendarTools.swift`**

```swift
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
```

- [ ] **Step 8: Run to see all pass, then commit**

```bash
xcodebuild -project gcalex.xcodeproj -scheme gcalex -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:gcalexTests/CalendarToolsTests -only-testing:gcalexTests/ISODateParsingTests
git add gcalex/AI gcalexTests/ISODateParsingTests.swift gcalexTests/CalendarToolsTests.swift
git commit -m "feat: add ConfirmationCenter and calendar Tools for Foundation Models"
```

---

## Task 6: ChatEngine

**Files:**
- Create: `gcalex/AI/ChatEngine.swift`

**Interfaces:**
- Consumes: `ListEventsTool`, `CreateEventTool`, `UpdateEventTool`,
  `DeleteEventTool`, `ConfirmationCenter` (Task 5), `EventStore`,
  `GoogleCalendarServicing` (Tasks 2, 4).
- Produces: `struct ChatMessage: Identifiable, Equatable { enum Role { case
  user, assistant }; let id: UUID; let role: Role; let text: String }` and
  `@Observable final class ChatEngine { private(set) var messages:
  [ChatMessage]; let confirmationCenter: ConfirmationCenter; init(eventStore:
  EventStore, calendarService: GoogleCalendarServicing, confirmationCenter:
  ConfirmationCenter, today: Date = Date()); func send(_ text: String) async
  }`. Consumed by Task 8 (`ChatView`) and Task 11 (app wiring).

This task's `session.respond(to:)` call against the real on-device model is
not unit tested — per spec section 9, on-device inference is non-deterministic
and the Tool logic it depends on is already covered in Task 5. `ChatEngine`
is verified manually in Task 11's app smoke test (send a real multi-day
message on-device and confirm the right Tools fire).

- [ ] **Step 1: Write `ChatEngine.swift`**

```swift
import Foundation
import Observation
import FoundationModels

struct ChatMessage: Identifiable, Equatable {
    enum Role: Equatable {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    let text: String
}

@Observable
final class ChatEngine {
    private(set) var messages: [ChatMessage] = []
    let confirmationCenter: ConfirmationCenter
    private let session: LanguageModelSession

    init(
        eventStore: EventStore,
        calendarService: GoogleCalendarServicing,
        confirmationCenter: ConfirmationCenter,
        today: Date = Date()
    ) {
        self.confirmationCenter = confirmationCenter
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd (EEEE)"
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = .current
        let instructions = """
        당신은 사용자의 구글 캘린더 일정을 관리하는 비서입니다.
        오늘 날짜는 \(formatter.string(from: today))입니다.
        일정을 특정할 때 참조가 모호하면 반드시 listEvents로 먼저 조회한 뒤
        updateEvent나 deleteEvent를 호출하세요.
        여러 날짜(예: 월/수/금)에 일정을 만들어 달라는 요청은 반복 규칙이 아니라
        각 날짜마다 createEvent를 한 번씩 호출해서 처리하세요.
        모든 응답은 한국어 존댓말로 간결하게 답하세요.
        """
        self.session = LanguageModelSession(
            tools: [
                ListEventsTool(eventStore: eventStore),
                CreateEventTool(calendarService: calendarService),
                UpdateEventTool(calendarService: calendarService, confirmationCenter: confirmationCenter),
                DeleteEventTool(calendarService: calendarService, confirmationCenter: confirmationCenter)
            ],
            instructions: instructions
        )
    }

    func send(_ text: String) async {
        messages.append(ChatMessage(role: .user, text: text))
        do {
            let response = try await session.respond(to: text)
            messages.append(ChatMessage(role: .assistant, text: response.content))
        } catch {
            messages.append(ChatMessage(role: .assistant, text: "무슨 뜻인지 잘 모르겠어요, 다시 말씀해주시겠어요?"))
        }
    }
}
```

- [ ] **Step 2: Build to confirm it compiles against FoundationModels**

```bash
xcodebuild -project gcalex.xcodeproj -scheme gcalex -destination 'generic/platform=iOS Simulator' build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add gcalex/AI/ChatEngine.swift
git commit -m "feat: add ChatEngine driving LanguageModelSession with calendar Tools"
```

---

## Task 7: CalendarMonthView (UICalendarView wrapper)

**Files:**
- Create: `gcalex/UI/CalendarMonthView.swift`

**Interfaces:**
- Consumes: `CalendarEvent` (Task 2) — caller supplies `Set<DateComponents>`
  for decoration, not raw events, so this view has no dependency on
  `EventStore` directly.
- Produces: `struct CalendarMonthView: UIViewRepresentable { init(eventDates:
  Set<DateComponents>, onSelect: @escaping (Date) -> Void) }`. Consumed by
  Task 11 (app wiring / main screen).

No unit test — `UIViewRepresentable` wrapping a native picker is verified
by manual/visual testing per spec section 9. This is not skipped work: it
gets exercised in Task 11's manual app walkthrough.

- [ ] **Step 1: Write `CalendarMonthView.swift`**

```swift
import SwiftUI
import UIKit

struct CalendarMonthView: UIViewRepresentable {
    let eventDates: Set<DateComponents>
    let onSelect: (Date) -> Void

    func makeUIView(context: Context) -> UICalendarView {
        let view = UICalendarView()
        view.calendar = Calendar(identifier: .gregorian)
        view.delegate = context.coordinator
        let selection = UICalendarSelectionSingleDate(delegate: context.coordinator)
        view.selectionBehavior = selection
        return view
    }

    func updateUIView(_ uiView: UICalendarView, context: Context) {
        context.coordinator.eventDates = eventDates
        uiView.reloadDecorations(forDateComponents: Array(eventDates), animated: true)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(eventDates: eventDates, onSelect: onSelect)
    }

    final class Coordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
        var eventDates: Set<DateComponents>
        let onSelect: (Date) -> Void

        init(eventDates: Set<DateComponents>, onSelect: @escaping (Date) -> Void) {
            self.eventDates = eventDates
            self.onSelect = onSelect
        }

        func calendarView(_ calendarView: UICalendarView, decorationFor dateComponents: DateComponents) -> UICalendarView.Decoration? {
            guard eventDates.contains(dateComponents) else { return nil }
            return .default(color: .systemBlue, size: .small)
        }

        func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate dateComponents: DateComponents?) {
            guard let dateComponents, let date = Calendar(identifier: .gregorian).date(from: dateComponents) else { return }
            onSelect(date)
        }
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild -project gcalex.xcodeproj -scheme gcalex -destination 'generic/platform=iOS Simulator' build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add gcalex/UI/CalendarMonthView.swift
git commit -m "feat: add CalendarMonthView wrapping UICalendarView"
```

---

## Task 8: DayDetailSheet and ChatView

**Files:**
- Create: `gcalex/UI/ChatView.swift`
- Create: `gcalex/UI/DayDetailSheet.swift`

**Interfaces:**
- Consumes: `ChatEngine`, `ChatMessage`, `ConfirmationCenter` (Task 6, 5),
  `CalendarEvent` (Task 2).
- Produces: `struct ChatView: View { let chatEngine: ChatEngine }` and
  `struct DayDetailSheet: View { let date: Date; let events: [CalendarEvent];
  let chatEngine: ChatEngine }`. Consumed by Task 11 (main screen sheet
  presentation).

No unit tests — SwiftUI view bodies are verified by manual/visual testing
per spec section 9 (exercised in Task 11).

- [ ] **Step 1: Write `ChatView.swift`**

```swift
import SwiftUI

struct ChatView: View {
    let chatEngine: ChatEngine
    @State private var draft: String = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(chatEngine.messages) { message in
                        HStack {
                            if message.role == .assistant { Spacer(minLength: 0) }
                            Text(message.text)
                                .padding(10)
                                .background(message.role == .user ? Color.blue.opacity(0.15) : Color.gray.opacity(0.15))
                                .cornerRadius(12)
                            if message.role == .user { Spacer(minLength: 0) }
                        }
                    }
                }
                .padding(12)
            }

            if let pending = chatEngine.confirmationCenter.pendingRequest {
                VStack(spacing: 8) {
                    Text(pending.message)
                        .font(.subheadline)
                    HStack {
                        Button("취소", role: .cancel) {
                            chatEngine.confirmationCenter.resolve(false)
                        }
                        Button("확인") {
                            chatEngine.confirmationCenter.resolve(true)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(12)
                .background(Color.yellow.opacity(0.15))
            }

            HStack {
                TextField("예: 월/수/금 오후 1시부터 3시까지 미팅", text: $draft)
                    .textFieldStyle(.roundedBorder)
                Button("전송") {
                    let text = draft
                    draft = ""
                    Task { await chatEngine.send(text) }
                }
                .disabled(draft.isEmpty)
            }
            .padding(12)
        }
    }
}
```

- [ ] **Step 2: Write `DayDetailSheet.swift`**

```swift
import SwiftUI

struct DayDetailSheet: View {
    let date: Date
    let events: [CalendarEvent]
    let chatEngine: ChatEngine

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "M월 d일 (EEEE)"
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(dateFormatter.string(from: date))
                .font(.headline)
                .padding()

            if events.isEmpty {
                Text("일정이 없습니다")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else {
                List(events) { event in
                    VStack(alignment: .leading) {
                        Text(event.title).font(.body)
                        Text("\(timeFormatter.string(from: event.startDate)) - \(timeFormatter.string(from: event.endDate))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .listStyle(.plain)
                .frame(maxHeight: 200)
            }

            Divider()

            ChatView(chatEngine: chatEngine)
        }
    }
}
```

- [ ] **Step 3: Build**

```bash
xcodebuild -project gcalex.xcodeproj -scheme gcalex -destination 'generic/platform=iOS Simulator' build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add gcalex/UI/ChatView.swift gcalex/UI/DayDetailSheet.swift
git commit -m "feat: add DayDetailSheet and ChatView UI"
```

---

## Task 9: NotificationScheduler

**Files:**
- Create: `gcalex/Notifications/NotificationScheduler.swift`
- Test: `gcalexTests/NotificationSchedulerTests.swift`

**Interfaces:**
- Consumes: `CalendarEvent` (Task 2).
- Produces: `enum NotificationContentBuilder { static func dailyAgendaText(
  todayEvents: [CalendarEvent], tomorrowEvents: [CalendarEvent]) -> String }`
  and `final class NotificationScheduler { init(center:
  UNUserNotificationCenter = .current()); func requestAuthorization() async
  throws -> Bool; func scheduleDailyAgenda(at time: DateComponents,
  todayEvents: [CalendarEvent], tomorrowEvents: [CalendarEvent]) async }`.
  Consumed by Task 10 (background refresh) and Task 11 (app wiring).

- [ ] **Step 1: Write the failing test for `NotificationContentBuilder`**

```swift
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
```

- [ ] **Step 2: Run to see it fail**

```bash
xcodebuild -project gcalex.xcodeproj -scheme gcalex -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:gcalexTests/NotificationSchedulerTests
```

Expected: FAIL — `NotificationContentBuilder` does not exist.

- [ ] **Step 3: Implement `NotificationScheduler.swift`**

```swift
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
```

- [ ] **Step 4: Run to see it pass, then commit**

```bash
xcodebuild -project gcalex.xcodeproj -scheme gcalex -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:gcalexTests/NotificationSchedulerTests
git add gcalex/Notifications gcalexTests/NotificationSchedulerTests.swift
git commit -m "feat: add NotificationScheduler with pure agenda text builder"
```

---

## Task 10: Background refresh (BGTaskScheduler)

**Files:**
- Create: `gcalex/App/BackgroundRefreshCoordinator.swift`

**Interfaces:**
- Consumes: `EventStore` (Task 4), `NotificationScheduler` (Task 9).
- Produces: `final class BackgroundRefreshCoordinator { init(eventStore:
  EventStore, notificationScheduler: NotificationScheduler,
  notificationTimeProvider: @escaping () -> DateComponents); func
  register(); func scheduleNextRefresh() }`. Consumed by Task 11 (app entry
  point calls `register()` at launch and `scheduleNextRefresh()` after each
  successful sync).

The task identifier `com.gsw226.gcalex.refresh` was already declared in
`project.yml` (Task 1) under `BGTaskSchedulerPermittedIdentifiers`.

No automated test — `BGTaskScheduler` execution timing is controlled by iOS
and cannot be triggered deterministically in a test target. It is verified
manually in Task 11 via Xcode's `e5yiv0` debug command
(`e -l objc -- (void)[[BGTaskScheduler sharedScheduler]
_simulateLaunchForTaskWithIdentifier:@"com.gsw226.gcalex.refresh"]`) during
the app smoke test.

- [ ] **Step 1: Write `BackgroundRefreshCoordinator.swift`**

```swift
import Foundation
import BackgroundTasks

final class BackgroundRefreshCoordinator {
    static let taskIdentifier = "com.gsw226.gcalex.refresh"

    private let eventStore: EventStore
    private let notificationScheduler: NotificationScheduler
    private let notificationTimeProvider: () -> DateComponents

    init(
        eventStore: EventStore,
        notificationScheduler: NotificationScheduler,
        notificationTimeProvider: @escaping () -> DateComponents
    ) {
        self.eventStore = eventStore
        self.notificationScheduler = notificationScheduler
        self.notificationTimeProvider = notificationTimeProvider
    }

    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { [weak self] task in
            guard let self, let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handle(refreshTask)
        }
    }

    func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handle(_ task: BGAppRefreshTask) {
        scheduleNextRefresh()
        let refreshOperation = Task {
            do {
                let calendar = Calendar.current
                let today = Date()
                let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
                try await eventStore.refresh(from: today, to: tomorrow)
                let todayEvents = await eventStore.events(on: today)
                let tomorrowEvents = await eventStore.events(on: tomorrow)
                await notificationScheduler.scheduleDailyAgenda(
                    at: notificationTimeProvider(),
                    todayEvents: todayEvents,
                    tomorrowEvents: tomorrowEvents
                )
                task.setTaskCompleted(success: true)
            } catch {
                task.setTaskCompleted(success: false)
            }
        }
        task.expirationHandler = { refreshOperation.cancel() }
    }
}
```

`BackgroundRefreshCoordinator.register()` is not called yet — it needs an
`EventStore` and `NotificationScheduler` instance to inject, and those are
only constructed once in Task 11's `AppEnvironment`. Wiring happens there
(Task 11, Step 2), not here.

- [ ] **Step 2: Build**

```bash
xcodebuild -project gcalex.xcodeproj -scheme gcalex -destination 'generic/platform=iOS Simulator' build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add gcalex/App/BackgroundRefreshCoordinator.swift
git commit -m "feat: add BackgroundRefreshCoordinator for BGTaskScheduler"
```

---

## Task 11: SettingsView and final app wiring

**Files:**
- Create: `gcalex/UI/SettingsView.swift`
- Create: `gcalex/App/RootView.swift`
- Modify: `gcalex/App/GcalexApp.swift`
- Modify: `gcalex/App/ContentView.swift` (delete — replaced by `RootView`)

**Interfaces:**
- Consumes: everything from Tasks 2–10.
- Produces: the fully wired app. No further tasks depend on this one.

- [ ] **Step 1: Write `SettingsView.swift`**

```swift
import SwiftUI

struct SettingsView: View {
    let authService: AuthServicing
    @Binding var notificationHour: Int
    @Binding var notificationMinute: Int
    let onSignInTapped: () -> Void
    let onSignOutTapped: () -> Void

    var body: some View {
        Form {
            Section("구글 계정") {
                if authService.isSignedIn {
                    Button("연결 해제", role: .destructive, action: onSignOutTapped)
                } else {
                    Button("구글 캘린더 연결", action: onSignInTapped)
                }
            }

            Section("알림 시각") {
                Stepper("\(notificationHour)시", value: $notificationHour, in: 0...23)
                Stepper("\(notificationMinute)분", value: $notificationMinute, in: 0...59, step: 5)
            }
        }
        .navigationTitle("설정")
    }
}
```

- [ ] **Step 2: Write `RootView.swift`**

```swift
import SwiftUI
import UIKit

@Observable
final class AppEnvironment {
    let authService: AuthServicing
    let calendarService: GoogleCalendarServicing
    let eventStore: EventStore
    let confirmationCenter: ConfirmationCenter
    let chatEngine: ChatEngine
    let notificationScheduler: NotificationScheduler
    let backgroundRefreshCoordinator: BackgroundRefreshCoordinator
    var notificationHour: Int = 8
    var notificationMinute: Int = 0

    init() {
        let authService = GoogleAuthService()
        let calendarService = GoogleCalendarService(tokenProvider: authService.accessToken)
        let eventStore = EventStore(calendarService: calendarService)
        let confirmationCenter = ConfirmationCenter()
        let chatEngine = ChatEngine(
            eventStore: eventStore,
            calendarService: calendarService,
            confirmationCenter: confirmationCenter
        )
        let notificationScheduler = NotificationScheduler()

        self.authService = authService
        self.calendarService = calendarService
        self.eventStore = eventStore
        self.confirmationCenter = confirmationCenter
        self.chatEngine = chatEngine
        self.notificationScheduler = notificationScheduler
        self.backgroundRefreshCoordinator = BackgroundRefreshCoordinator(
            eventStore: eventStore,
            notificationScheduler: notificationScheduler,
            notificationTimeProvider: { [weak self] in
                DateComponents(hour: self?.notificationHour ?? 8, minute: self?.notificationMinute ?? 0)
            }
        )
    }
}

struct RootView: View {
    @State private var environment = AppEnvironment()
    @State private var selectedDate: Date?
    @State private var eventDates: Set<DateComponents> = []
    @State private var eventsBySelectedDate: [CalendarEvent] = []

    var body: some View {
        NavigationStack {
            VStack {
                CalendarMonthView(eventDates: eventDates) { date in
                    selectedDate = date
                    Task { await loadEvents(for: date) }
                }
            }
            .navigationTitle("gcalex")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink("설정") {
                        SettingsView(
                            authService: environment.authService,
                            notificationHour: $environment.notificationHour,
                            notificationMinute: $environment.notificationMinute,
                            onSignInTapped: signIn,
                            onSignOutTapped: { environment.authService.signOut() }
                        )
                    }
                }
            }
            .sheet(item: Binding(
                get: { selectedDate.map { IdentifiedDate(date: $0) } },
                set: { selectedDate = $0?.date }
            )) { identified in
                DayDetailSheet(date: identified.date, events: eventsBySelectedDate, chatEngine: environment.chatEngine)
            }
        }
        .task {
            await environment.authService.restorePreviousSignIn()
            environment.backgroundRefreshCoordinator.register()
            _ = try? await environment.notificationScheduler.requestAuthorization()
            await refreshMonth()
        }
    }

    private func signIn() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        Task { try? await environment.authService.signIn(presentingViewController: root) }
    }

    private func refreshMonth() async {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -7, to: Date())!
        let end = calendar.date(byAdding: .day, value: 30, to: Date())!
        try? await environment.eventStore.refresh(from: start, to: end)
        let all = await environment.eventStore.allEvents
        eventDates = Set(all.map { calendar.dateComponents([.year, .month, .day], from: $0.startDate) })
    }

    private func loadEvents(for date: Date) async {
        eventsBySelectedDate = await environment.eventStore.events(on: date)
    }
}

private struct IdentifiedDate: Identifiable {
    let date: Date
    var id: TimeInterval { date.timeIntervalSince1970 }
}
```

- [ ] **Step 3: Update `GcalexApp.swift` to use `RootView`**

```swift
import SwiftUI
import GoogleSignIn

@main
struct GcalexApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
```

- [ ] **Step 4: Delete `ContentView.swift` and its reference**

```bash
git rm gcalex/App/ContentView.swift
```

Also delete `SmokeTests.swift`'s reference to `ContentView` — replace its
body with a trivial pass-through check against `RootView` instead:

```swift
import Testing
@testable import gcalex

struct SmokeTests {
    @Test func rootViewBuilds() {
        _ = RootView()
    }
}
```

- [ ] **Step 5: Build and run the full test suite**

```bash
xcodebuild -project gcalex.xcodeproj -scheme gcalex -destination 'generic/platform=iOS Simulator' build
xcodebuild -project gcalex.xcodeproj -scheme gcalex -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Expected: `** BUILD SUCCEEDED **` and all tests pass.

- [ ] **Step 6: Manual smoke test on a physical iPhone 15 Pro (iOS 26+)**

Simulators cannot run Foundation Models inference or present the real Google
Sign-In flow, so this step must run on the physical device from the spec
(iPhone 15 Pro, per spec section 2):

1. Build & run on-device from Xcode (`Product > Run`, destination = your
   iPhone).
2. Tap "설정" → "구글 캘린더 연결", sign in with your Google account, grant
   the calendar scope.
3. Return to the main screen; confirm dots appear on days that already have
   events in your real calendar.
4. Tap a date, type: `월/수/금 오후 1시부터 3시까지 미팅` — confirm three
   events get created on the correct dates without a confirmation prompt.
5. Type: `방금 만든 미팅 4시로 미뤄줘` — confirm a confirmation card appears
   before anything changes, and tapping "확인" actually shifts the event
   (verify in the Google Calendar app), while tapping "취소" leaves it
   untouched.
6. Type: `그 미팅 취소해줘` for one of the remaining events — confirm the
   same confirm/cancel gating before deletion.
7. In Settings, set the notification time a couple of minutes in the future,
   background the app, and confirm the local notification fires with a body
   like "오늘: ...\n내일: ...".

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: wire SettingsView, RootView, and app entry point together"
```

---

## Self-Review Notes

- **Spec coverage:** section 3 (architecture) → Tasks 1–6, 10; section 4
  (UX) → Tasks 7–8, 11; section 5 (data flow, including the zero-event
  notification case) → Tasks 4, 9, 10; section 6 (AI command scope,
  including multi-date non-recurring creation) → Task 5's `CreateEventTool`
  + Task 6's session instructions; section 7 (error handling) → Task 6's
  catch branch, Task 5's confirmation-cancel paths, Task 11 step 6's manual
  auth-expiry-adjacent checks; section 8 (security) → Task 3's reliance on
  Google Sign-In's Keychain-backed store, PKCE via `GIDSignIn`; section 9
  (testing) → every task's Test file plus explicit manual-test call-outs for
  UI/SDK-bound code; section 10 (MVP exclusions) → no task builds a calendar
  picker, RRULE support, widget, Watch app, or cloud fallback.
- **Placeholder scan:** no TBD/TODO remain; the one literal substitution
  (`REVERSED_CLIENT_ID_PLACEHOLDER` in Task 1) is called out explicitly as a
  one-time value from the developer's own Google Cloud project, not an
  implementation gap.
- **Type consistency:** `CalendarEvent` (Task 2) is used with the same
  three-field shape everywhere it appears (Tasks 4, 5, 6, 8, 9, 10, 11).
  `GoogleCalendarServicing`'s four method signatures introduced in Task 2 are
  called identically in Tasks 4, 5, and 11. `ConfirmationCenter`'s
  `pendingRequest`/`requestConfirmation`/`resolve` names introduced in Task 5
  are the same ones read in Task 8's `ChatView` and driven in Task 5's tests.
