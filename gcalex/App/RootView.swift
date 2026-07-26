import SwiftUI
import UIKit

/// Storage for the user's chosen daily-notification time, shared between
/// `AppEnvironment` (which exposes it to `SettingsView` as `@MainActor`
/// `@Observable` state) and `BackgroundRefreshCoordinator`'s
/// `notificationTimeProvider` closure.
///
/// `BackgroundRefreshCoordinator` requires that closure to be a *synchronous*
/// `@Sendable () -> DateComponents` (see `App/BackgroundRefreshCoordinator.swift`),
/// and it is invoked from inside a `BGTaskScheduler` launch handler, which runs
/// off the main actor with no opportunity to `await` onto it. That means the
/// closure cannot read `AppEnvironment`'s `@MainActor`-isolated
/// `notificationHour`/`notificationMinute` properties directly — doing so would
/// be a main-actor isolation violation, not merely a style choice. Routing both
/// the UI-facing properties and the background-read closure through
/// `UserDefaults` (a thread-safe, `Sendable`-friendly API) sidesteps that
/// conflict entirely and, as a side benefit, persists the user's chosen time
/// across app relaunches, which an in-memory-only property would not.
private enum NotificationTimeDefaults {
    static let hourKey = "gcalex.notificationHour"
    static let minuteKey = "gcalex.notificationMinute"
    static let defaultHour = 8
    static let defaultMinute = 0

    static func read() -> DateComponents {
        let defaults = UserDefaults.standard
        let hour = defaults.object(forKey: hourKey) as? Int ?? defaultHour
        let minute = defaults.object(forKey: minuteKey) as? Int ?? defaultMinute
        return DateComponents(hour: hour, minute: minute)
    }
}

/// Owns every service/store/coordinator Tasks 2–10 produced and wires them
/// together for the UI layer.
///
/// **Actor isolation:** pinned to `@MainActor`, because its `init()` must
/// construct `ConfirmationCenter()` and `ChatEngine(...)` synchronously —
/// both are `@MainActor`-isolated types (see their own files), and this
/// project's `SWIFT_VERSION` is 6.0 with no project-wide default actor
/// isolation configured, so a plain `nonisolated` initializer could not call
/// their initializers without an `await` hop. Marking the whole class
/// `@MainActor` also matches how it's used: it's held as `@State` inside
/// `RootView`, a SwiftUI `View` whose `body` — and, by the compiler's
/// protocol-conformance isolation inference, the whole conforming type — is
/// already main-actor-isolated. `AppEnvironment` itself is never made
/// `Sendable` and never needs to be: it's never sent across an isolation
/// boundary as a value, only read from the main actor.
@MainActor
@Observable
final class AppEnvironment {
    let authService: AuthServicing
    let calendarService: GoogleCalendarServicing
    let eventStore: EventStore
    let confirmationCenter: ConfirmationCenter
    let chatEngine: ChatEngine
    let notificationScheduler: NotificationScheduler
    let backgroundRefreshCoordinator: BackgroundRefreshCoordinator

    /// Observable mirror of `authService.isSignedIn`. `authService.isSignedIn`
    /// is a computed property over `GIDSignIn.sharedInstance.currentUser` with
    /// no observability, so the UI can't re-render when sign-in state changes.
    /// This `@Observable` property is updated right after every
    /// sign-in/out/restore call so `SettingsView` can track it.
    var isSignedIn: Bool = false

    var notificationHour: Int {
        didSet {
            UserDefaults.standard.set(notificationHour, forKey: NotificationTimeDefaults.hourKey)
            rescheduleNotification()
        }
    }
    var notificationMinute: Int {
        didSet {
            UserDefaults.standard.set(notificationMinute, forKey: NotificationTimeDefaults.minuteKey)
            rescheduleNotification()
        }
    }

    /// Re-schedules the daily-agenda notification at the newly-chosen time using
    /// currently-cached events, so a Settings time change takes effect
    /// immediately instead of waiting for the next background refresh. The
    /// time-provider closure reads `UserDefaults`, which the `didSet`s above have
    /// already updated by the time this runs.
    private func rescheduleNotification() {
        Task { await backgroundRefreshCoordinator.rescheduleNotificationFromCache() }
    }

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

        let initialTime = NotificationTimeDefaults.read()
        self.notificationHour = initialTime.hour ?? NotificationTimeDefaults.defaultHour
        self.notificationMinute = initialTime.minute ?? NotificationTimeDefaults.defaultMinute

        self.backgroundRefreshCoordinator = BackgroundRefreshCoordinator(
            eventStore: eventStore,
            notificationScheduler: notificationScheduler,
            notificationTimeProvider: { NotificationTimeDefaults.read() }
        )
    }
}

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

private struct IdentifiedDate: Identifiable {
    let date: Date
    var id: TimeInterval { date.timeIntervalSince1970 }
}
