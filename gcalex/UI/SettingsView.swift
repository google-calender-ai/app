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
