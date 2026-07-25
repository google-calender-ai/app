import SwiftUI

struct ChatView: View {
    let chatEngine: ChatEngine
    @State private var draft: String = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(chatEngine.messages) { message in
                        HStack {
                            if message.role == .assistant { Spacer(minLength: 0) }
                            Text(message.text)
                                .padding(10)
                                .glassEffect(
                                    message.role == .user ? .regular.tint(.blue) : .regular,
                                    in: RoundedRectangle(cornerRadius: 12)
                                )
                            if message.role == .user { Spacer(minLength: 0) }
                        }
                    }
                }
                .padding(12)
            }

            if let pending = chatEngine.confirmationCenter.pendingRequest {
                VStack(spacing: 8) {
                    Text(pending.message)
                        .font(.subheadline)
                    HStack {
                        Button("취소", role: .cancel) {
                            chatEngine.confirmationCenter.resolve(false)
                        }
                        .buttonStyle(.glass)
                        Button("확인") {
                            chatEngine.confirmationCenter.resolve(true)
                        }
                        .buttonStyle(.glassProminent)
                    }
                }
                .padding(12)
                .glassEffect(.regular.tint(.yellow), in: RoundedRectangle(cornerRadius: 12))
            }

            HStack {
                TextField("예: 월/수/금 오후 1시부터 3시까지 미팅", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .disabled(chatEngine.isProcessing)
                Button("전송") {
                    let text = draft
                    draft = ""
                    Task { await chatEngine.send(text) }
                }
                .buttonStyle(.glassProminent)
                .disabled(draft.isEmpty || chatEngine.isProcessing)
            }
            .padding(12)
        }
    }
}
