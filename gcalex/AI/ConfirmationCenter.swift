import Foundation
import Observation

struct ConfirmationRequest: Identifiable, Sendable {
    let id = UUID()
    let message: String
}

/// Coordinates confirmation prompts between background Tool calls (which run off the
/// caller's actor, see `Tool.call(arguments:)`) and the SwiftUI layer (Task 8's
/// DayDetailSheet, which reads `pendingRequest` on the main actor).
///
/// `ConfirmationCenter` is pinned to `@MainActor` so all mutable state
/// (`pendingRequest`, `continuation`) is only ever touched from a single, serialized
/// isolation domain. That's what makes the explicit `Sendable` conformance below sound:
/// the class has `var` stored properties, but nothing outside the main actor can ever
/// observe or mutate them without first awaiting onto it, so there is no data race for
/// the compiler to miss — this is not `@unchecked`. If two Tool calls request
/// confirmation "at the same time", the second `requestConfirmation` call still only
/// runs after hopping onto the main actor, so it simply overwrites `pendingRequest`
/// and `continuation` in a well-defined, serialized order (no torn state); the caller
/// of the first request just never gets resolved by `resolve(_:)` for that specific
/// request. That's a UX question for Task 8 (e.g. queuing) rather than a memory-safety
/// one, so it's left as-is here.
@MainActor
@Observable
final class ConfirmationCenter: Sendable {
    private(set) var pendingRequest: ConfirmationRequest?
    private var continuation: CheckedContinuation<Bool, Never>?

    func requestConfirmation(message: String) async -> Bool {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.pendingRequest = ConfirmationRequest(message: message)
        }
    }

    func resolve(_ approved: Bool) {
        pendingRequest = nil
        continuation?.resume(returning: approved)
        continuation = nil
    }
}
