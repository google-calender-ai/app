import Foundation
// `BackgroundTasks` is an unaudited ObjC framework: its Swift overlay has
// no Sendable annotations at all (verified against the SDK header/apinotes
// — no `NS_SWIFT_SENDABLE`/`swift_attr` markers anywhere on `BGTask`,
// `BGAppRefreshTask`, or `BGTaskScheduler.register`'s `launchHandler`).
// `@preconcurrency` is the sanctioned way to interop with such a module:
// it tells the compiler this framework predates concurrency checking, so
// Sendable-related diagnostics about its types are treated leniently
// instead of hard errors. This is not a stand-in for `@unchecked
// Sendable` on our own code — nothing in this file claims a type it owns
// is Sendable when it isn't; it only relaxes how the *unaudited framework
// boundary* is checked, exactly as the framework's own header structure
// (or lack of annotations) calls for.
@preconcurrency import BackgroundTasks

final class BackgroundRefreshCoordinator {
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

    /// Registers the background refresh launch handler. Must be called
    /// before the app finishes launching (per `BGTaskScheduler`'s
    /// contract), and only once per task identifier for the lifetime of
    /// the process.
    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { [weak self] task in
            guard let self, let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handle(refreshTask)
        }
    }

    /// Submits the next background refresh request, roughly 4 hours out.
    /// Called at launch (after `register()`) and again at the start of
    /// every launch-handler invocation, to keep the refresh chain going.
    func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handle(_ task: BGAppRefreshTask) {
        scheduleNextRefresh()

        // Read the stored properties into locals before crossing into the
        // unstructured `Task` below. `eventStore` (an actor) and
        // `notificationScheduler`/`notificationTimeProvider` (genuinely
        // `Sendable`, see their own declarations) don't strictly need
        // this for safety, but it keeps the closure from capturing `self`
        // (a plain, non-Sendable class) implicitly through property
        // access, which is its own, separate Sendable violation.
        let eventStore = eventStore
        let notificationScheduler = notificationScheduler
        let notificationTimeProvider = notificationTimeProvider

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
