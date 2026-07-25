# gcalex Calendar Visual Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Color weekend dates (Sunday red, Saturday blue) in gcalex's calendar and give the app a consistent iOS 26 Liquid Glass visual tone, without changing any AI/calendar-sync behavior.

**Architecture:** Replace `CalendarMonthView.swift`'s `UICalendarView` wrapper with a pure SwiftUI month grid (its public interface is unchanged, so no other file needs to know about the swap) built on two new pure-function helpers (`WeekdayColor`, `MonthGrid`) that carry the only genuinely testable logic. Apply Apple's real iOS 26 `glassEffect`/`GlassButtonStyle` APIs to the app's custom chrome — navigation header, chat bubbles, confirmation card, sheet container, settings buttons — while deliberately leaving the calendar's date-cell backgrounds plain for readability.

**Tech Stack:** SwiftUI, iOS 26 Liquid Glass APIs (`View.glassEffect(_:in:)`, `GlassButtonStyle`/`.glass`, `GlassProminentButtonStyle`/`.glassProminent`, all verified against the real `SwiftUICore.swiftinterface` under the iOS 26.5 simulator SDK), Swift Testing (`import Testing`).

## Global Constraints

- Deployment target iOS 26.0+, Swift 6 strict concurrency (`SWIFT_VERSION: "6.0"`) — from `gcalex/project.yml`. None of this plan's new types are `async` or hold shared mutable state, so no new actor-isolation/`Sendable` work is needed; do not add `@unchecked Sendable` anywhere (established, enforced project rule).
- Weekend color mapping: Sunday = `.red`, Saturday = `.blue`, all other weekdays = `.primary` — from spec section 4.1. Applied to both the date number and the weekday header letter.
- Only Saturday/Sunday get colored — no real Korean public holidays in this scope — from spec section 2.
- Liquid Glass is applied to: the month header/navigation row, `DayDetailSheet`'s container, `ChatView`'s message bubbles/confirmation card/send button, `SettingsView`'s account buttons — from spec section 4.2.
- Liquid Glass is deliberately NOT applied to the calendar grid's date-cell backgrounds (readability) — from spec section 4.2.
- Today's date cell has a solid blue circle background; if today falls on a Saturday/Sunday, the number drawn on that circle is white (not the weekday color) so it stays legible against the fill — from spec section 4.1 (as amended in spec self-review).
- No AI/calendar-sync files (`ChatEngine.swift`, `CalendarTools.swift`, `GoogleCalendarService.swift`, `EventStore.swift`, `NotificationScheduler.swift`, `BackgroundRefreshCoordinator.swift`) are touched by this plan — from spec section 5.
- Project convention: app sources live at `gcalex/gcalex/<Module>/<File>.swift`, tests at `gcalex/gcalexTests/<File>.swift`, relative to the repo root `/Users/gangsang-u/Documents/GitHub/gcalex`. After adding or changing any source file, run `xcodegen generate` (from `gcalex/`) before building/testing, or the change can silently fail to be picked up.
- Build/test commands (run from `/Users/gangsang-u/Documents/GitHub/gcalex/gcalex`):
  ```
  xcodegen generate
  xcodebuild -project gcalex.xcodeproj -scheme gcalex -destination 'generic/platform=iOS Simulator' build
  xcodebuild -project gcalex.xcodeproj -scheme gcalex -destination 'platform=iOS Simulator,name=iPhone 17' test
  ```

---

## Task 1: WeekdayColor and MonthGrid pure-function helpers

**Files:**
- Create: `gcalex/gcalex/UI/WeekdayColor.swift`
- Create: `gcalex/gcalex/UI/MonthGrid.swift`
- Test: `gcalex/gcalexTests/WeekdayColorTests.swift`
- Test: `gcalex/gcalexTests/MonthGridTests.swift`

**Interfaces:**
- Consumes: nothing (pure, standalone logic).
- Produces: `enum WeekdayColor { static func color(forWeekday weekday: Int) -> Color }` (Foundation `Calendar` 1-based weekday convention: Sunday = 1 ... Saturday = 7) and `enum MonthGrid { static func cells(for referenceDate: Date, calendar: Calendar) -> [Date?] }` (an array whose length is always a multiple of 7, with leading/trailing `nil` placeholders so real dates land under their correct weekday column). Both are consumed directly by Task 2's `CalendarMonthView` rewrite.

- [ ] **Step 1: Write the failing tests for `WeekdayColor`**

```swift
import Testing
import SwiftUI
@testable import gcalex

struct WeekdayColorTests {
    @Test func sundayIsRed() {
        #expect(WeekdayColor.color(forWeekday: 1) == .red)
    }

    @Test func saturdayIsBlue() {
        #expect(WeekdayColor.color(forWeekday: 7) == .blue)
    }

    @Test func weekdaysArePrimary() {
        for weekday in 2...6 {
            #expect(WeekdayColor.color(forWeekday: weekday) == .primary)
        }
    }
}
```

- [ ] **Step 2: Write the failing tests for `MonthGrid`**

```swift
import Testing
import Foundation
@testable import gcalex

struct MonthGridTests {
    @Test func julyTwoThousandTwentySixHasThreeLeadingBlanksAndOneTrailingBlank() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 7, day: 15))!

        let cells = MonthGrid.cells(for: referenceDate, calendar: calendar)

        // 2026-07-01 is a Wednesday (weekday 4), so 3 leading blanks precede it.
        #expect(cells[0] == nil)
        #expect(cells[1] == nil)
        #expect(cells[2] == nil)
        let firstDay = cells[3]
        #expect(firstDay != nil)
        #expect(calendar.component(.day, from: firstDay!) == 1)

        // 31 real days + 3 leading blanks = 34; padded to a multiple of 7 = 35, so 1 trailing blank.
        #expect(cells.count == 35)
        #expect(cells.last! == nil)
    }

    @Test func everyNonNilCellFallsWithinTheReferenceMonthInOrder() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 7, day: 1))!

        let cells = MonthGrid.cells(for: referenceDate, calendar: calendar)
        let daysPresent = cells.compactMap { $0 }.map { calendar.component(.day, from: $0) }

        #expect(daysPresent == Array(1...31))
    }
}
```

- [ ] **Step 3: Run the tests to see them fail**

```bash
cd /Users/gangsang-u/Documents/GitHub/gcalex
xcodegen generate
xcodebuild -project gcalex.xcodeproj -scheme gcalex -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:gcalexTests/WeekdayColorTests -only-testing:gcalexTests/MonthGridTests
```

Expected: FAIL — `WeekdayColor` and `MonthGrid` do not exist yet.

- [ ] **Step 4: Implement `WeekdayColor.swift`**

```swift
import SwiftUI

/// Maps a `Calendar`-style 1-based weekday (Sunday = 1 ... Saturday = 7) to
/// the color it should render in, both for the weekday header letter and the
/// date number itself.
enum WeekdayColor {
    static func color(forWeekday weekday: Int) -> Color {
        switch weekday {
        case 1: return .red
        case 7: return .blue
        default: return .primary
        }
    }
}
```

- [ ] **Step 5: Implement `MonthGrid.swift`**

```swift
import Foundation

/// Produces the ordered list of dates (with `nil` placeholders for
/// out-of-month blanks) to render in a 7-column month grid, so the first
/// real day of the month lands under its correct weekday column and the
/// final row is padded out to a full week.
enum MonthGrid {
    static func cells(for referenceDate: Date, calendar: Calendar) -> [Date?] {
        let monthInterval = calendar.dateInterval(of: .month, for: referenceDate)!
        let firstOfMonth = monthInterval.start
        let daysInMonth = calendar.range(of: .day, in: .month, for: referenceDate)!.count
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let leadingBlanks = firstWeekday - 1

        var cells: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for dayOffset in 0..<daysInMonth {
            cells.append(calendar.date(byAdding: .day, value: dayOffset, to: firstOfMonth))
        }

        let trailingBlanks = (7 - cells.count % 7) % 7
        cells.append(contentsOf: Array(repeating: nil, count: trailingBlanks))
        return cells
    }
}
```

- [ ] **Step 6: Run the tests to see them pass**

```bash
xcodebuild -project gcalex.xcodeproj -scheme gcalex -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:gcalexTests/WeekdayColorTests -only-testing:gcalexTests/MonthGridTests
```

Expected: PASS, 5/5 tests (3 in `WeekdayColorTests`, 2 in `MonthGridTests`).

- [ ] **Step 7: Commit**

```bash
git add gcalex/gcalex/UI/WeekdayColor.swift gcalex/gcalex/UI/MonthGrid.swift gcalex/gcalexTests/WeekdayColorTests.swift gcalex/gcalexTests/MonthGridTests.swift
git commit -m "feat: add WeekdayColor and MonthGrid pure-function helpers"
```

---

## Task 2: Rewrite CalendarMonthView as a native SwiftUI month grid

**Files:**
- Modify (full rewrite): `gcalex/gcalex/UI/CalendarMonthView.swift`

**Interfaces:**
- Consumes: `WeekdayColor.color(forWeekday:)` and `MonthGrid.cells(for:calendar:)` from Task 1.
- Produces: `struct CalendarMonthView: View` with the exact same public initializer as before — `init(calendar: Calendar, eventDates: Set<DateComponents>, onSelect: @escaping (Date) -> Void)`. This is unchanged from the current `UIViewRepresentable` version, so `RootView.swift`'s existing call site (`CalendarMonthView(calendar: displayCalendar, eventDates: eventDates) { date in ... }`) needs no changes — verified in Task 5.

This task has no automated tests — it's a SwiftUI view body, matching this project's established convention (verified by compilation, then manually in Task 5's simulator check).

- [ ] **Step 1: Replace the full contents of `gcalex/gcalex/UI/CalendarMonthView.swift`**

```swift
import SwiftUI

struct CalendarMonthView: View {
    let calendar: Calendar
    let eventDates: Set<DateComponents>
    let onSelect: (Date) -> Void

    @State private var visibleMonth: Date

    init(calendar: Calendar, eventDates: Set<DateComponents>, onSelect: @escaping (Date) -> Void) {
        self.calendar = calendar
        self.eventDates = eventDates
        self.onSelect = onSelect
        _visibleMonth = State(initialValue: Date())
    }

    private static let weekdaySymbols = ["일", "월", "화", "수", "목", "금", "토"]

    private var monthTitleFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월"
        return formatter
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    changeMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.glass)

                Spacer()
                Text(monthTitleFormatter.string(from: visibleMonth))
                    .font(.headline)
                Spacer()

                Button {
                    changeMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.glass)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .glassEffect(in: RoundedRectangle(cornerRadius: 20))

            HStack {
                ForEach(Array(Self.weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                    Text(symbol)
                        .font(.caption)
                        .foregroundStyle(WeekdayColor.color(forWeekday: index + 1))
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 12) {
                ForEach(Array(MonthGrid.cells(for: visibleMonth, calendar: calendar).enumerated()), id: \.offset) { _, date in
                    if let date {
                        dayCell(for: date)
                    } else {
                        Color.clear.frame(height: 36)
                    }
                }
            }
        }
    }

    private func dayCell(for date: Date) -> some View {
        let weekday = calendar.component(.weekday, from: date)
        let day = calendar.component(.day, from: date)
        let isToday = calendar.isDateInToday(date)
        let hasEvent = eventDates.contains(calendar.dateComponents([.year, .month, .day], from: date))

        return Button {
            onSelect(date)
        } label: {
            VStack(spacing: 4) {
                Text("\(day)")
                    .font(.body)
                    .foregroundStyle(isToday ? .white : WeekdayColor.color(forWeekday: weekday))
                    .frame(width: 32, height: 32)
                    .background {
                        if isToday {
                            Circle().fill(Color.blue)
                        }
                    }

                Circle()
                    .fill(Color.blue)
                    .frame(width: 4, height: 4)
                    .opacity(hasEvent ? 1 : 0)
            }
            .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.plain)
    }

    private func changeMonth(by offset: Int) {
        guard let newMonth = calendar.date(byAdding: .month, value: offset, to: visibleMonth) else { return }
        visibleMonth = newMonth
    }
}
```

Note on the `hasEvent` lookup: `calendar.dateComponents([.year, .month, .day], from: date)` only ever populates the year/month/day fields it was asked for, so it produces a `DateComponents` directly comparable to `RootView.refreshMonth()`'s `eventDates` (built the same way, with the same `displayCalendar` value passed in as `calendar`) — no extra truncation step is needed here, unlike the old `UICalendarView` coordinator, which had to truncate because the delegate handed back a `DateComponents` with extra fields it didn't ask for.

- [ ] **Step 2: Build to confirm it compiles cleanly**

```bash
cd /Users/gangsang-u/Documents/GitHub/gcalex
xcodegen generate
xcodebuild -project gcalex.xcodeproj -scheme gcalex -destination 'generic/platform=iOS Simulator' build
```

Expected: `** BUILD SUCCEEDED **`, no warnings.

- [ ] **Step 3: Commit**

```bash
git add gcalex/gcalex/UI/CalendarMonthView.swift
git commit -m "feat: replace UICalendarView wrapper with native SwiftUI month grid"
```

---

## Task 3: Liquid Glass on ChatView

**Files:**
- Modify: `gcalex/gcalex/UI/ChatView.swift`

**Interfaces:**
- Consumes: nothing new (same `ChatEngine`/`ConfirmationCenter` surface it already uses).
- Produces: same public interface `ChatView(chatEngine:)` — unchanged, so `DayDetailSheet.swift`'s existing call site needs no change.

No automated tests (SwiftUI view body). Both message bubble types get glass (not just the assistant one) so the chat feed doesn't look visually mismatched — the user bubble gets a blue-tinted glass, the assistant bubble a plain regular glass, which is the closest reading of "일관된 톤" that keeps both bubble types visually consistent with each other.

- [ ] **Step 1: Replace the full contents of `gcalex/gcalex/UI/ChatView.swift`**

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
                                .glassEffect(
                                    message.role == .user ? .regular.tint(.blue) : .regular,
                                    in: RoundedRectangle(cornerRadius: 12)
                                )
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
                        .buttonStyle(.glass)
                        Button("확인") {
                            chatEngine.confirmationCenter.resolve(true)
                        }
                        .buttonStyle(.glassProminent)
                    }
                }
                .padding(12)
                .glassEffect(.regular.tint(.yellow), in: RoundedRectangle(cornerRadius: 12))
            }

            HStack {
                TextField("예: 월/수/금 오후 1시부터 3시까지 미팅", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .disabled(chatEngine.isProcessing)
                Button("전송") {
                    let text = draft
                    draft = ""
                    Task { await chatEngine.send(text) }
                }
                .buttonStyle(.glassProminent)
                .disabled(draft.isEmpty || chatEngine.isProcessing)
            }
            .padding(12)
        }
    }
}
```

- [ ] **Step 2: Build to confirm it compiles cleanly**

```bash
cd /Users/gangsang-u/Documents/GitHub/gcalex
xcodegen generate
xcodebuild -project gcalex.xcodeproj -scheme gcalex -destination 'generic/platform=iOS Simulator' build
```

Expected: `** BUILD SUCCEEDED **`, no warnings.

- [ ] **Step 3: Commit**

```bash
git add gcalex/gcalex/UI/ChatView.swift
git commit -m "feat: apply Liquid Glass to chat bubbles, confirmation card, and buttons"
```

---

## Task 4: Liquid Glass on DayDetailSheet

**Files:**
- Modify: `gcalex/gcalex/UI/DayDetailSheet.swift`

**Interfaces:**
- Consumes: `ChatView(chatEngine:)` from Task 3 (unchanged interface).
- Produces: same public interface `DayDetailSheet(date:events:chatEngine:)` — unchanged, so `RootView.swift`'s existing `.sheet` call site needs no change.

No automated tests (SwiftUI view body). The event `List` gets `.scrollContentBackground(.hidden)` so its own default opaque background doesn't visually cut a hole through the sheet's new glass background.

- [ ] **Step 1: Replace the full contents of `gcalex/gcalex/UI/DayDetailSheet.swift`**

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
                .scrollContentBackground(.hidden)
                .frame(maxHeight: 200)
            }

            Divider()

            ChatView(chatEngine: chatEngine)
        }
        .glassEffect(in: RoundedRectangle(cornerRadius: 24))
        .onDisappear {
            // If the sheet is dismissed while a destructive-action confirmation
            // is still pending, resolve it as cancelled. Otherwise the stored
            // continuation is never resumed: the underlying `Tool.call` awaits
            // forever, `ChatEngine.isProcessing` stays `true`, and every later
            // `send(_:)` becomes a silent no-op.
            if chatEngine.confirmationCenter.pendingRequest != nil {
                chatEngine.confirmationCenter.resolve(false)
            }
        }
    }
}
```

- [ ] **Step 2: Build to confirm it compiles cleanly**

```bash
cd /Users/gangsang-u/Documents/GitHub/gcalex
xcodegen generate
xcodebuild -project gcalex.xcodeproj -scheme gcalex -destination 'generic/platform=iOS Simulator' build
```

Expected: `** BUILD SUCCEEDED **`, no warnings.

- [ ] **Step 3: Commit**

```bash
git add gcalex/gcalex/UI/DayDetailSheet.swift
git commit -m "feat: apply Liquid Glass to DayDetailSheet container"
```

---

## Task 5: Liquid Glass on SettingsView, RootView verification, and final visual check

**Files:**
- Modify: `gcalex/gcalex/UI/SettingsView.swift`
- Verify only (no expected changes): `gcalex/gcalex/App/RootView.swift`

**Interfaces:**
- Consumes: `AppEnvironment` (unchanged), `CalendarMonthView` from Task 2 (unchanged public interface), `DayDetailSheet` from Task 4 (unchanged public interface).
- Produces: nothing new for later tasks — this is the last task in the plan.

No automated tests. This task also confirms the app's standard `NavigationStack` toolbar (the "설정" button) needs no explicit glass code — on iOS 26 it already renders with the system's automatic Liquid Glass treatment, which was directly observed in this session's own simulator screenshot of the unmodified app (the "설정" button already appeared as a soft translucent pill with no glass-related code anywhere in `RootView.swift`).

- [ ] **Step 1: Replace the full contents of `gcalex/gcalex/UI/SettingsView.swift`**

```swift
import SwiftUI

struct SettingsView: View {
    // Read directly from the `@Observable` `AppEnvironment` so this view
    // re-renders when sign-in state changes. `authService.isSignedIn` (a
    // computed property over `GIDSignIn.sharedInstance.currentUser`) carries no
    // observability, so binding to it left the button stale after sign-in/out.
    @Bindable var environment: AppEnvironment
    let onSignInTapped: () -> Void
    let onSignOutTapped: () -> Void

    var body: some View {
        Form {
            Section("구글 계정") {
                if environment.isSignedIn {
                    Button("연결 해제", role: .destructive, action: onSignOutTapped)
                        .buttonStyle(.glass)
                } else {
                    Button("구글 캘린더 연결", action: onSignInTapped)
                        .buttonStyle(.glassProminent)
                }
            }

            Section("알림 시각") {
                Stepper("\(environment.notificationHour)시", value: $environment.notificationHour, in: 0...23)
                Stepper("\(environment.notificationMinute)분", value: $environment.notificationMinute, in: 0...59, step: 5)
            }
        }
        .navigationTitle("설정")
    }
}
```

- [ ] **Step 2: Confirm `RootView.swift` needs no changes**

Read `gcalex/gcalex/App/RootView.swift` and confirm its `CalendarMonthView(calendar: displayCalendar, eventDates: eventDates) { date in ... }` call site (around the `body`'s `VStack`) and its `DayDetailSheet(date: identified.date, events: eventsBySelectedDate, chatEngine: environment.chatEngine)` call site (inside `.sheet(item:)`) still match Task 2's and Task 4's unchanged public initializers exactly. No edit is expected — this step is a verification, not a code change.

- [ ] **Step 3: Build and run the full test suite**

```bash
cd /Users/gangsang-u/Documents/GitHub/gcalex
xcodegen generate
xcodebuild -project gcalex.xcodeproj -scheme gcalex -destination 'generic/platform=iOS Simulator' build
xcodebuild -project gcalex.xcodeproj -scheme gcalex -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Expected: `** BUILD SUCCEEDED **` and all tests pass (18 pre-existing + 5 new from Task 1 = 23 tests across 8 suites), pristine output.

- [ ] **Step 4: Commit the SettingsView change**

```bash
git add gcalex/gcalex/UI/SettingsView.swift
git commit -m "feat: apply Liquid Glass to SettingsView account buttons"
```

- [ ] **Step 5: Manual visual verification on the iPhone 15 Pro (iOS 26) simulator**

Build and install onto a real iPhone 15 Pro simulator running iOS 26 (not the pre-existing iOS 18.6 "iPhone 15 Pro" simulator, which cannot run this app's iOS 26.0 deployment target — create a fresh one if needed, following the exact recipe already used earlier in this project's session):

```bash
cd /Users/gangsang-u/Documents/GitHub/gcalex
SIM_ID=$(xcrun simctl list devices | grep "iPhone 15 Pro (iOS 26)" | grep -oE '[0-9A-F-]{36}' | head -1)
if [ -z "$SIM_ID" ]; then
  SIM_ID=$(xcrun simctl create "iPhone 15 Pro (iOS 26)" com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro com.apple.CoreSimulator.SimRuntime.iOS-26-5)
fi
xcodebuild -project gcalex.xcodeproj -scheme gcalex -destination "id=$SIM_ID" build
xcrun simctl boot "$SIM_ID" 2>&1 || true
open -a Simulator --args -CurrentDeviceUDID "$SIM_ID"
xcrun simctl bootstatus "$SIM_ID" -b
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -path "*Debug-iphonesimulator/gcalex.app" -maxdepth 6 2>/dev/null | head -1)
xcrun simctl install "$SIM_ID" "$APP_PATH"
xcrun simctl launch "$SIM_ID" com.gsw226.gcalex
sleep 2
xcrun simctl io "$SIM_ID" screenshot /tmp/gcalex-visual-redesign-check.png
```

Read the resulting screenshot and confirm:
- The weekday header row shows "일" in red and "토" in blue, with the other five in the default text color.
- Date numbers follow the same red/blue/default pattern down each column.
- Today's date has a filled blue circle behind it, with a white number.
- Tapping a date still opens the bottom sheet (previously verified interaction — re-confirm it isn't broken).
- The month header row, the bottom sheet, chat bubbles, and settings buttons all show a visibly translucent/glassy material rather than flat opaque colors.
- The calendar grid's date cells themselves do NOT have a glass background — only plain text/circle on the normal background.

If anything above doesn't hold, note the discrepancy for the task reviewer rather than silently adjusting the design.

---

## Self-Review Notes

- **Spec coverage:** section 2 (weekend-only scope) → Task 1's `WeekdayColor` has no holiday logic; section 4.1 (grid rebuild, color placement, today's white-on-blue text) → Task 2; section 4.2 (Liquid Glass application list and the explicit calendar-grid exclusion) → Tasks 2 (header only, not day cells), 3, 4, 5; section 5 (affected/excluded files) → matches exactly, no AI/sync file appears in any task's Files list; section 7 (pure-function unit tests) → Task 1; section 8 (out of scope: real holidays, glass on date cells, AI logic changes) → nothing in any task touches these.
- **Placeholder scan:** no TBD/TODO/"add appropriate styling"-style steps; every code block is complete, ready-to-use Swift.
- **Type consistency:** `WeekdayColor.color(forWeekday:)` and `MonthGrid.cells(for:calendar:)` (Task 1) are called with the same names/signatures in Task 2. `CalendarMonthView`'s init signature (Task 2) is asserted unchanged in Task 5's verification step against the same call site read from the current `RootView.swift`. `ChatView(chatEngine:)` (Task 3) and `DayDetailSheet(date:events:chatEngine:)` (Task 4) keep their pre-existing signatures, referenced identically in Task 5.
