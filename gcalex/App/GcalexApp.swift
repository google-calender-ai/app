import SwiftUI
import GoogleSignIn

@main
struct GcalexApp: App {
    // Single source of truth for the app's services/stores/coordinators. Held
    // here (rather than inside `RootView`) so the scene-level
    // `.backgroundTask(.appRefresh:)` modifier below can reach the same
    // `AppEnvironment` instance `RootView` uses — there must be exactly one.
    @State private var environment = AppEnvironment()

    var body: some Scene {
        // Capture just the coordinator (a genuinely `Sendable` value type of
        // immutable `Sendable` fields) so the `@Sendable` background-task
        // closure never captures the non-`Sendable`, `@MainActor` `AppEnvironment`.
        let coordinator = environment.backgroundRefreshCoordinator
        return WindowGroup {
            RootView(environment: environment)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
        // Registering the background-refresh handler as a scene modifier means
        // it is wired up as part of scene setup — before the app finishes
        // launching — which is exactly what `BGTaskScheduler` requires. Doing
        // the old manual `BGTaskScheduler.shared.register(...)` from a view's
        // `.task` fired too late (after first render) and could silently fail.
        .backgroundTask(.appRefresh(BackgroundRefreshCoordinator.taskIdentifier)) {
            await coordinator.performBackgroundRefresh()
        }
    }
}
