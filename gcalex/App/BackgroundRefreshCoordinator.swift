import Foundation
// `BackgroundTasks` is an unaudited ObjC framework: its Swift overlay has no
// Sendable annotations at all. `@preconcurrency` is the sanctioned way to
// interop with such a module — it tells the compiler this framework predates
// concurrency checking, so Sendable-related diagnostics about its types
// (`BGTaskScheduler`, `BGAppRefreshTaskRequest`) are treated leniently instead
// of hard errors. This is not a stand-in for `@unchecked Sendable` on our own
// code — nothing here claims a type it owns is Sendable when it isn't; it only
// relaxes how the *unaudited framework boundary* is checked. Handler
// registration itself no longer happens here: it's done via SwiftUI's
// `.backgroundTask(.appRefresh:)` scene modifier in `GcalexApp`, which registers
// before launch finishes (as `BGTaskScheduler` requires).
@preconcurrency import BackgroundTasks

/// Genuinely `Sendable` (not `@unchecked`): all three stored properties are
/// immutable `let`s of `Sendable` types — `EventStore` (an actor),
/// `NotificationScheduler` (declared `Sendable`), and a `@Sendable` closure — so
/// there is no mutable state for concurrent callers to race on. Being `Sendable`
/// lets `GcalexApp`'s `@Sendable` `.backgroundTask` closure capture this
/// coordinator directly instead of the non-`Sendable` `AppEnvironment`.
final class BackgroundRefreshCoordinator: Sendable {
    static let taskIdentifier = "com.gsw226.gcalex.refresh"

    private let eventStore: EventStore
    private let notificationScheduler: NotificationScheduler
    private let notificationTimeProvider: @Sendable () -> DateComponents

    init(
        eventStore: EventStore,
        notificationScheduler: NotificationScheduler,
        notificationTimeProvider: @escaping @Sendable () -> DateComponents
    ) {
        self.eventStore = eventStore
        self.notificationScheduler = notificationScheduler
        self.notificationTimeProvider = notificationTimeProvider
    }

    /// Submits the next background refresh request, roughly 4 hours out.
    /// Called on a foreground launch and again at the start of every
    /// background-refresh cycle, to keep the refresh chain going.
    func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 60 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Non-fatal: iOS refuses submissions in some states (Low Power Mode,
            // too many pending requests, background refresh disabled). We simply
            // don't get a background wake this cycle; the next foreground launch
            // re-submits. Logging (rather than swallowing) keeps it debuggable.
            print("gcalex: BGTaskScheduler.submit failed: \(error)")
        }
    }

    /// The full background-refresh cycle, invoked from `GcalexApp`'s
    /// `.backgroundTask(.appRefresh:)` scene handler: queue the next background
    /// attempt, pull the latest today/tomorrow events over the network, then
    /// (re)schedule the daily-agenda notification from that fresh data.
    func performBackgroundRefresh() async {
        scheduleNextRefresh()
        let calendar = Calendar.current
        let today = Date()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        try? await eventStore.refresh(from: today, to: tomorrow)
        await rescheduleNotificationFromCache()
    }

    /// (Re)schedules the daily-agenda notification from whatever events are
    /// already cached in `eventStore` — no network fetch. Called on a normal
    /// foreground launch right after the month refresh (so a fresh install gets
    /// its first notification scheduled immediately from current data, rather
    /// than only after some future background task fires) and whenever the user
    /// changes the notification time in Settings.
    func rescheduleNotificationFromCache() async {
        let calendar = Calendar.current
        let today = Date()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let todayEvents = await eventStore.events(on: today)
        let tomorrowEvents = await eventStore.events(on: tomorrow)
        await notificationScheduler.scheduleDailyAgenda(
            at: notificationTimeProvider(),
            todayEvents: todayEvents,
            tomorrowEvents: tomorrowEvents
        )
    }
}
