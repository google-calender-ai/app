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
                } else {
                    Button("구글 캘린더 연결", action: onSignInTapped)
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
