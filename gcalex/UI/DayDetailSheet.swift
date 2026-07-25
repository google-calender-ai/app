import SwiftUI

struct DayDetailSheet: View {
    let date: Date
    let events: [CalendarEvent]
    let chatEngine: ChatEngine

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "M월 d일 (EEEE)"
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(dateFormatter.string(from: date))
                .font(.headline)
                .padding()

            if events.isEmpty {
                Text("일정이 없습니다")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else {
                List(events) { event in
                    VStack(alignment: .leading) {
                        Text(event.title).font(.body)
                        Text("\(timeFormatter.string(from: event.startDate)) - \(timeFormatter.string(from: event.endDate))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(maxHeight: 200)
            }

            Divider()

            ChatView(chatEngine: chatEngine)
        }
        .glassEffect(in: RoundedRectangle(cornerRadius: 24))
        .onDisappear {
            // If the sheet is dismissed while a destructive-action confirmation
            // is still pending, resolve it as cancelled. Otherwise the stored
            // continuation is never resumed: the underlying `Tool.call` awaits
            // forever, `ChatEngine.isProcessing` stays `true`, and every later
            // `send(_:)` becomes a silent no-op.
            if chatEngine.confirmationCenter.pendingRequest != nil {
                chatEngine.confirmationCenter.resolve(false)
            }
        }
    }
}
