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
        let refreshedUser = try await user.refreshTokensIfNeeded()
        return refreshedUser.accessToken.tokenString
    }
}
