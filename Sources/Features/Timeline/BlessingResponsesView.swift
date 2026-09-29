import SwiftUI

struct BlessingResponsesView: View {
    @Environment(AppModel.self) private var model
    let blessing: Blessing

    @State private var responses: [BlessingResponse] = []
    @State private var mode: ResponseMode = .typed
    @State private var text = ""
    @State private var isLoading = true
    @State private var isSending = false
    @State private var transcriber = SpeechTranscriber()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Responses")
                    .font(.headline)
                Spacer()
                if isLoading { ProgressView().controlSize(.small) }
            }

            if !isLoading && responses.isEmpty {
                Text("No responses yet. Add a word of encouragement.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryInk)
            }

            ForEach(responses) { response in
                responseRow(response)
            }

            Divider()
            Picker("Response type", selection: $mode) {
                ForEach(ResponseMode.allCases) { option in
                    Label(option.title, systemImage: option.systemImage).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) {
                transcriber.reset()
                text = ""
            }

            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 92)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(AppTheme.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 12).stroke(AppTheme.divider) }
                .onChange(of: text) { _, value in
                    if value.count > 600 { text = String(value.prefix(600)) }
                }
                .accessibilityLabel(mode == .voice ? "Voice response transcript" : "Text response")

            if mode == .voice {
                Button {
                    Task { await transcriber.toggle() }
                } label: {
                    Label(
                        transcriber.state == .listening ? "Stop recording" : "Record response",
                        systemImage: transcriber.state == .listening ? "stop.fill" : "waveform"
                    )
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }

            Button {
                send()
            } label: {
                HStack {
                    Label("Send response", systemImage: "arrow.up.circle.fill")
                    if isSending { ProgressView().tint(.white) }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSend || isSending)
        }
        .blessingCard()
        .task(id: blessing.id) {
            responses = await model.responses(for: blessing)
            isLoading = false
        }
        .onChange(of: transcriber.transcript) { _, value in
            text = String(value.prefix(600))
        }
        .onDisappear { transcriber.stop() }
    }

    @ViewBuilder
    private func responseRow(_ response: BlessingResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(displayName(for: response.authorID))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(response.submittedAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryInk)
            }
            if response.mode == .voice, let audioURL = response.audioURL {
                AudioBlessingPlayer(url: audioURL)
            }
            Text(response.body)
                .font(.subheadline)
                .textSelection(.enabled)
        }
        .padding(12)
        .background(AppTheme.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var canSend: Bool {
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if mode == .typed { return hasText }
        return hasText && transcriber.recordingURL != nil && transcriber.state != .listening
    }

    private func send() {
        transcriber.stop()
        let audioURL = mode == .voice ? transcriber.recordingURL : nil
        isSending = true
        Task {
            if let response = await model.submitResponse(
                to: blessing,
                mode: mode,
                body: text,
                audioURL: audioURL
            ) {
                responses.append(response)
                text = ""
                transcriber.reset()
            }
            isSending = false
        }
    }

    private func displayName(for memberID: UUID) -> String {
        if memberID == model.currentUser?.id { return "You" }
        return model.circle?.members.first(where: { $0.id == memberID })?.displayName ?? "Circle member"
    }
}
