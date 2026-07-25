import Foundation
import Observation
import FoundationModels

struct ChatMessage: Identifiable, Equatable {
    enum Role: Equatable {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    let text: String
}

/// Drives a `LanguageModelSession` wired to the calendar `Tool`s (Task 5), holding the
/// chat transcript for Task 8's `ChatView` and exposing `ConfirmationCenter` so the UI
/// can render pending confirmation cards.
///
/// **Actor isolation:** `ChatEngine` is pinned to `@MainActor`, mirroring
/// `ConfirmationCenter`'s precedent (Task 5). Its `messages`/`isProcessing` are mutated
/// by `send(_:)` and are meant to be read directly (no `await`) by SwiftUI view bodies
/// (Task 8's `ChatView`), so under Swift 6 strict concurrency that state needs a single,
/// UI-affine isolation domain — the same reasoning Task 5 used for `ConfirmationCenter`'s
/// `pendingRequest`. This is not a rubber-stamped `@unchecked Sendable`: `ChatEngine`
/// isn't declared `Sendable` at all (nothing requires crossing it across isolation
/// domains — no `Tool` stores a `ChatEngine`), it is simply MainActor-isolated like any
/// ordinary SwiftUI model object.
///
/// Calling `session.respond(to:)` directly from this `@MainActor` method is correct and
/// does not block the main thread: the real FoundationModels SDK declares
/// `respond(to:)` `nonisolated(nonsending)` (confirmed via the compiled
/// `FoundationModels.swiftinterface`, see task report), meaning it runs on the
/// *caller's* isolation domain rather than hopping to a background executor — it still
/// suspends properly at its internal `await` points, freeing the main thread for other
/// work while waiting. The individual `Tool.call(arguments:)` invocations the session
/// makes internally are separately marked `@concurrent` in the SDK, so tool logic (e.g.
/// network calls in `CreateEventTool`) always runs off the main actor regardless.
@MainActor
@Observable
final class ChatEngine {
    private(set) var messages: [ChatMessage] = []
    let confirmationCenter: ConfirmationCenter
    private let session: LanguageModelSession

    /// Serializes turns so at most one `session.respond(to:)` call is ever in flight.
    ///
    /// `ConfirmationCenter.requestConfirmation` (Task 5) has no request queue: a second
    /// `requestConfirmation()` call that starts while one is already pending silently
    /// overwrites the first's stored continuation, hanging the first caller forever.
    /// Apple's tool-calling loop inside a single `session.respond(to:)` call is
    /// sequential, so that's safe *within* one turn — but nothing about `send(_:)`
    /// itself stops a second call from starting a second `session.respond(to:)` while
    /// the first is still in flight (e.g. mid-confirmation), which would hit exactly
    /// that bug. `isProcessing` makes an overlapping `send(_:)` call a no-op instead, so
    /// at most one `respond(to:)` — and therefore at most one live confirmation
    /// request — is ever outstanding.
    ///
    /// This is race-free specifically because `ChatEngine` is `@MainActor`-isolated:
    /// the guard-check-then-set below (`guard !isProcessing else { return };
    /// isProcessing = true`) is a single synchronous block with no `await` in between,
    /// and a Swift actor only ever runs one task's code at a time between suspension
    /// points. If a second `Task { await chatEngine.send(...) }` is scheduled while the
    /// first is suspended inside `respond(to:)`, that second task's invocation of
    /// `send(_:)` cannot start running until the actor is free to schedule it, and by
    /// then `isProcessing` is already `true` — there's no window where two calls can
    /// both read `isProcessing == false` before either one sets it, so two overlapping
    /// `send(_:)` calls can never both reach `session.respond(to:)`.
    private(set) var isProcessing = false

    init(
        eventStore: EventStore,
        calendarService: GoogleCalendarServicing,
        confirmationCenter: ConfirmationCenter,
        today: Date = Date()
    ) {
        self.confirmationCenter = confirmationCenter
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd (EEEE)"
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = .current
        let instructions = """
        당신은 사용자의 구글 캘린더 일정을 관리하는 비서입니다.
        오늘 날짜는 \(formatter.string(from: today))입니다.
        일정을 특정할 때 참조가 모호하면 반드시 listEvents로 먼저 조회한 뒤
        updateEvent나 deleteEvent를 호출하세요.
        여러 날짜(예: 월/수/금)에 일정을 만들어 달라는 요청은 반복 규칙이 아니라
        각 날짜마다 createEvent를 한 번씩 호출해서 처리하세요.
        모든 응답은 한국어 존댓말로 간결하게 답하세요.
        """
        self.session = LanguageModelSession(
            tools: [
                ListEventsTool(eventStore: eventStore),
                CreateEventTool(calendarService: calendarService),
                UpdateEventTool(calendarService: calendarService, confirmationCenter: confirmationCenter),
                DeleteEventTool(calendarService: calendarService, confirmationCenter: confirmationCenter)
            ],
            instructions: instructions
        )
    }

    func send(_ text: String) async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        messages.append(ChatMessage(role: .user, text: text))
        do {
            let response = try await session.respond(to: text)
            messages.append(ChatMessage(role: .assistant, text: response.content))
        } catch {
            messages.append(ChatMessage(role: .assistant, text: "무슨 뜻인지 잘 모르겠어요, 다시 말씀해주시겠어요?"))
        }
    }
}
