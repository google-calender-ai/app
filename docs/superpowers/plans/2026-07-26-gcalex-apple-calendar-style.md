# gcalex Apple Calendar-Style UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make gcalex's main calendar screen feel closer to Apple's own Calendar app — red "today" indicator, larger typography, a real navigation-bar month/year title with swipe-to-change-month, and a conditional "오늘" (Today) button that returns to the current month — without touching AI/sync logic or adding any of Apple Calendar's other screens (multi-calendar, week/day/year views, search).

**Architecture:** `CalendarMonthView` stops owning its own navigation chrome (title, chevrons, glass header) and becomes a pure "render this month, let the caller drive which month" component: `visibleMonth` moves from its own private `@State` to a `@Binding` supplied by `RootView`, and a `DragGesture` on the view replaces the removed header's chevron buttons as the primary way to change months. `RootView` becomes the one place that owns `visibleMonth`, renders it as the real `.navigationTitle`, offers small chevron buttons in the toolbar as a discoverable secondary way to change months, and shows a bottom "오늘" button whenever the visible month isn't the current one.

**Tech Stack:** SwiftUI (`@Binding`, `DragGesture`, `.safeAreaInset(edge:)`, `.navigationTitle`/`.navigationBarTitleDisplayMode`), the same iOS 26 Liquid Glass APIs already used elsewhere in this app (`.buttonStyle(.glassProminent)`).

## Global Constraints

- Today's date cell background circle changes from `Color.blue` to `Color.red` — the number stays white. Event dots stay `Color.blue` (unchanged) — from spec section 3.1.
- Date number font: `.system(size: 20, weight: .medium)` (was `.body`). Weekday header font: `.caption` + `.fontWeight(.medium)` (was `.caption` with no weight). Day-cell minimum height: 44pt (was 36pt) — from spec section 3.1.
- Saturday stays `.blue` via the existing, unchanged `WeekdayColor.color(forWeekday:)` — do NOT touch `WeekdayColor.swift` or `MonthGrid.swift` — from spec section 2.
- `CalendarMonthView`'s public interface changes this round (unlike the prior visual-redesign plan): `init(calendar: Calendar, eventDates: Set<DateComponents>, visibleMonth: Binding<Date>, onSelect: @escaping (Date) -> Void)` — from spec section 3.2.
- `CalendarMonthView` no longer renders its own header (title, chevron buttons, glass pill) — month navigation happens via a `DragGesture` (swipe) on the view itself. `RootView` is the only place with visible month-navigation chrome (toolbar chevrons + nav title) — from spec section 3.2–3.3.
- Swipe gesture: attach `.simultaneousGesture(DragGesture(minimumDistance: 30))` to the container wrapping the weekday-header row and the grid (not to individual day-cell buttons), so day taps and the swipe don't conflict. A completed drag only changes the month if `abs(translation.width) >= 50` — from spec section 3.2.
- `RootView`'s `.navigationTitle("gcalex")` is replaced by the visible month/year (`"yyyy년 M월"`, Korean locale) as the real navigation title, with `.navigationBarTitleDisplayMode(.large)` — from spec section 3.3.
- The bottom "오늘" button only appears when `displayCalendar.isDate(visibleMonth, equalTo: Date(), toGranularity: .month)` is `false`, uses `.buttonStyle(.glassProminent)`, and tapping it sets `visibleMonth = Date()` — from spec section 3.3.
- No changes to `WeekdayColor.swift`, `MonthGrid.swift`, `ChatView.swift`, `DayDetailSheet.swift`, `SettingsView.swift`, or any AI/sync file (`ChatEngine.swift`, `CalendarTools.swift`, `GoogleCalendarService.swift`, `EventStore.swift`, `NotificationScheduler.swift`, `BackgroundRefreshCoordinator.swift`) — from spec section 4.
- `RootView.refreshMonth()`'s fixed `today-7...today+30` event-fetch window is unchanged — widening it for arbitrary visible months is explicitly out of scope for this plan (spec section 7 / prior final review already noted this as a pre-existing limitation, not something this plan fixes).
- Project convention: app sources at `gcalex/gcalex/<Module>/<File>.swift`, relative to repo root `/Users/gangsang-u/Documents/GitHub/gcalex` (or the current worktree's `gcalex/` if working in an isolated worktree). After changing source files, run `xcodegen generate` (from `gcalex/`) before building/testing, or changes can silently fail to be picked up.
- Build/test commands (run from the project's `gcalex/` directory):
  ```
  xcodegen generate
  xcodebuild -project gcalex.xcodeproj -scheme gcalex -destination 'generic/platform=iOS Simulator' build
  xcodebuild -project gcalex.xcodeproj -scheme gcalex -destination 'platform=iOS Simulator,name=iPhone 17' test
  ```

---

## Task 1: Lift `visibleMonth` to RootView, rebuild navigation chrome, apply Apple-style visual polish

This is one task, not split further, because `CalendarMonthView`'s new `Binding<Date>` parameter and `RootView`'s new call site are two halves of a single interface change — splitting them would leave the project non-compiling between tasks (the old `RootView` call site cannot satisfy the new `CalendarMonthView` initializer, and vice versa).

**Files:**
- Modify (full rewrite): `gcalex/gcalex/UI/CalendarMonthView.swift`
- Modify: `gcalex/gcalex/App/RootView.swift`

**Interfaces:**
- Consumes: `WeekdayColor.color(forWeekday:)` and `MonthGrid.cells(for:calendar:)` (both unchanged, from an earlier plan) inside `CalendarMonthView`. `AppEnvironment`, `SettingsView(environment:onSignInTapped:onSignOutTapped:)`, `DayDetailSheet(date:events:chatEngine:)` (all unchanged) inside `RootView`.
- Produces: `CalendarMonthView`'s new public interface `init(calendar: Calendar, eventDates: Set<DateComponents>, visibleMonth: Binding<Date>, onSelect: @escaping (Date) -> Void)`. Nothing outside this task consumes it — `RootView` is both the sole caller and part of this same task.

No automated tests — this is SwiftUI view/gesture/navigation code, matching this project's established convention (verified by compilation, then manually on a simulator).

- [ ] **Step 1: Replace the full contents of `gcalex/gcalex/UI/CalendarMonthView.swift`**

```swift
import SwiftUI

struct CalendarMonthView: View {
    let calendar: Calendar
    let eventDates: Set<DateComponents>
    @Binding var visibleMonth: Date
    let onSelect: (Date) -> Void

    private static let weekdaySymbols = ["일", "월", "화", "수", "목", "금", "토"]
    private static let swipeThreshold: CGFloat = 50

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                ForEach(Array(Self.weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                    Text(symbol)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(WeekdayColor.color(forWeekday: index + 1))
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 12) {
                ForEach(Array(MonthGrid.cells(for: visibleMonth, calendar: calendar).enumerated()), id: \.offset) { _, date in
                    if let date {
                        dayCell(for: date)
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if value.translation.width <= -Self.swipeThreshold {
                        changeMonth(by: 1)
                    } else if value.translation.width >= Self.swipeThreshold {
                        changeMonth(by: -1)
                    }
                }
        )
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
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isToday ? .white : WeekdayColor.color(forWeekday: weekday))
                    .frame(width: 32, height: 32)
                    .background {
                        if isToday {
                            Circle().fill(Color.red)
                        }
                    }

                Circle()
                    .fill(Color.blue)
                    .frame(width: 4, height: 4)
                    .opacity(hasEvent ? 1 : 0)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
    }

    private func changeMonth(by offset: Int) {
        guard let newMonth = calendar.date(byAdding: .month, value: offset, to: visibleMonth) else { return }
        visibleMonth = newMonth
    }
}
```

- [ ] **Step 2: Update `gcalex/gcalex/App/RootView.swift`'s `RootView` struct**

Only the `RootView` struct (starting at `struct RootView: View {`) changes — `NotificationTimeDefaults` and `AppEnvironment` above it, and `IdentifiedDate` below it, are untouched. Replace the `RootView` struct with:

```swift
struct RootView: View {
    @Bindable var environment: AppEnvironment
    @State private var selectedDate: Date?
    @State private var eventDates: Set<DateComponents> = []
    @State private var eventsBySelectedDate: [CalendarEvent] = []
    @State private var visibleMonth: Date = Date()

    /// The single source of truth for turning `Date`s into `DateComponents`.
    /// `CalendarMonthView`'s `dayCell(for:)` looks up each day via
    /// `eventDates.contains(calendar.dateComponents([.year, .month, .day], from: date))`,
    /// so `eventDates` must be built with the exact same `Calendar` value or
    /// `Set.contains` can spuriously miss a day.
    private let displayCalendar = Calendar(identifier: .gregorian)

    private var monthTitleFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = displayCalendar
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월"
        return formatter
    }

    private var isViewingCurrentMonth: Bool {
        displayCalendar.isDate(visibleMonth, equalTo: Date(), toGranularity: .month)
    }

    var body: some View {
        NavigationStack {
            VStack {
                CalendarMonthView(calendar: displayCalendar, eventDates: eventDates, visibleMonth: $visibleMonth) { date in
                    selectedDate = date
                    Task { await loadEvents(for: date) }
                }
            }
            .navigationTitle(monthTitleFormatter.string(from: visibleMonth))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        changeVisibleMonth(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        changeVisibleMonth(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink("설정") {
                        SettingsView(
                            environment: environment,
                            onSignInTapped: signIn,
                            onSignOutTapped: {
                                environment.authService.signOut()
                                environment.isSignedIn = environment.authService.isSignedIn
                            }
                        )
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !isViewingCurrentMonth {
                    Button("오늘") {
                        withAnimation {
                            visibleMonth = Date()
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .padding(.bottom, 8)
                    .transition(.opacity)
                }
            }
            .animation(.default, value: isViewingCurrentMonth)
            .sheet(item: Binding(
                get: { selectedDate.map { IdentifiedDate(date: $0) } },
                set: { selectedDate = $0?.date }
            )) { identified in
                DayDetailSheet(date: identified.date, events: eventsBySelectedDate, chatEngine: environment.chatEngine)
                    .presentationBackground(.clear)
            }
        }
        .task {
            await environment.authService.restorePreviousSignIn()
            environment.isSignedIn = environment.authService.isSignedIn
            environment.backgroundRefreshCoordinator.scheduleNextRefresh()
            _ = try? await environment.notificationScheduler.requestAuthorization()
            await refreshMonth()
            // Schedule the first daily-agenda notification immediately from the
            // freshly-refreshed cache, so a fresh install doesn't have to wait
            // for a future background task (which may fire hours away, or never).
            await environment.backgroundRefreshCoordinator.rescheduleNotificationFromCache()
        }
    }

    private func changeVisibleMonth(by offset: Int) {
        guard let newMonth = displayCalendar.date(byAdding: .month, value: offset, to: visibleMonth) else { return }
        visibleMonth = newMonth
    }

    private func signIn() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        Task {
            try? await environment.authService.signIn(presentingViewController: root)
            environment.isSignedIn = environment.authService.isSignedIn
            await refreshMonth()
        }
    }

    private func refreshMonth() async {
        let calendar = displayCalendar
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
```

- [ ] **Step 3: Build to confirm clean compilation**

```bash
cd /Users/gangsang-u/Documents/GitHub/gcalex
xcodegen generate
xcodebuild -project gcalex.xcodeproj -scheme gcalex -destination 'generic/platform=iOS Simulator' build
```

Expected: `** BUILD SUCCEEDED **`, no warnings.

- [ ] **Step 4: Run the full test suite (regression check — this task adds no new tests)**

```bash
xcodebuild -project gcalex.xcodeproj -scheme gcalex -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Expected: `** TEST SUCCEEDED **`, all pre-existing tests still passing, pristine output.

- [ ] **Step 5: Commit**

```bash
git add gcalex/gcalex/UI/CalendarMonthView.swift gcalex/gcalex/App/RootView.swift
git commit -m "feat: Apple Calendar-style navigation and visual polish"
```

- [ ] **Step 6: Manual visual verification on the iPhone 15 Pro (iOS 26) simulator**

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
xcrun simctl io "$SIM_ID" screenshot /tmp/gcalex-apple-style-check.png
```

Read the resulting screenshot and confirm:
- The navigation title shows "2026년 7월" (or the current real month/year) as a large title — no "gcalex" text anywhere on screen.
- Small chevron-left and chevron-right buttons appear in the toolbar (leading and trailing), alongside "설정" on the trailing side.
- Today's date cell has a **red** filled circle with a white number (not blue).
- Date numbers are visibly larger than before, with more breathing room between rows.
- Since the app launches on the current month, the bottom "오늘" button should NOT be visible (only appears when viewing a different month) — if you can trigger a month change (e.g. by adjusting the simulator's date or another mechanism), confirm the button appears then and disappears when back on the current month.

If anything above doesn't hold, note the discrepancy for the task reviewer rather than silently adjusting the design.

---

## Self-Review Notes

- **Spec coverage:** section 3.1 (today=red, typography, spacing) → Step 1's `dayCell(for:)`; section 3.2 (`visibleMonth` binding, swipe gesture, header removal) → Step 1's full `CalendarMonthView` body + `changeMonth`; section 3.3 (navigation title, toolbar chevrons, bottom Today button) → Step 2's `RootView` body; section 4 (only these two files touched) → matches the plan's Files list exactly; section 7 (no fetch-window widening) → `refreshMonth()` reproduced byte-for-byte unchanged in Step 2.
- **Placeholder scan:** no TBD/TODO; every step has complete, ready-to-use Swift.
- **Type consistency:** `CalendarMonthView`'s new init parameter order/names (`calendar:eventDates:visibleMonth:onSelect:`) match exactly between its own declaration (Step 1) and `RootView`'s call site (Step 2). `WeekdayColor.color(forWeekday:)` and `MonthGrid.cells(for:calendar:)` are called with their existing, unchanged signatures.
