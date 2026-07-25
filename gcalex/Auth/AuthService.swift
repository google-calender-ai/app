import Foundation
import UIKit
import GoogleSignIn

/// `Sendable`-constrained (Task 11) so a bound `accessToken` method value —
/// e.g. `authService.accessToken`, used by `AppEnvironment` to build
/// `GoogleCalendarService`'s `@Sendable () async throws -> String`
/// token-provider closure — can itself be treated as `@Sendable` under
/// Swift 6 strict concurrency. See `GoogleAuthService`'s own conformance
/// below for why this is sound and not `@unchecked`.
protocol AuthServicing: AnyObject, Sendable {
    var isSignedIn: Bool { get }
    func restorePreviousSignIn() async
    func signIn(presentingViewController: UIViewController) async throws
    func signOut()
    func accessToken() async throws -> String
}

enum AuthError: Error, Equatable {
    case notSignedIn
}

/// Genuinely `Sendable` (not `@unchecked`): `GoogleAuthService` has no
/// stored properties at all — every method simply delegates to
/// `GIDSignIn.sharedInstance`, so there is no mutable state on this type for
/// concurrent callers to race on, and the compiler can verify that directly.
final class GoogleAuthService: AuthServicing, Sendable {
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
        let refreshedUser = try await user.refreshTokensIfNeeded()
        return refreshedUser.accessToken.tokenString
    }
}
