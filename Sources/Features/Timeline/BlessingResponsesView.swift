import SwiftUI

struct BlessingResponsesView: View {
    @Environment(AppModel.self) private var model
    let blessing: Blessing
    let allowsResponding: Bool
    var showsHeading = true
    var usesCard = true

    @State private var responses: [BlessingResponse] = []
    @State private var mode: ResponseMode = .typed
    @State private var text = ""
    @State private var isLoading = true
    @State private var isSending = false
    @State private var transcriber = SpeechTranscriber()
    @FocusState private var composerFocused: Bool

    var body: some View {
        Group {
            if allowsResponding || isLoading || !responses.isEmpty {
                if usesCard {
                    responseContent.blessingCard()
                } else {
                    responseContent
                }
            }
        }
        .task(id: "\(blessing.id)-\(model.savedBlessings[blessing.id]?.savedAt.timeIntervalSince1970 ?? 0)") {
            responses = await model.responses(for: blessing)
            isLoading = false
        }
        .onChange(of: transcriber.transcript) { _, value in
            text = String(value.prefix(600))
        }
        .onChange(of: composerFocused) { _, isFocused in
            guard isFocused, transcriber.state != .listening else { return }
            mode = .typed
            if transcriber.recordingURL != nil { transcriber.reset() }
        }
        .onDisappear { transcriber.stop() }
    }

    private var responseContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsHeading && (isLoading || !responses.isEmpty) {
                HStack {
                    Text("Responses")
                        .font(.headline)
                    Spacer()
                    if isLoading { ProgressView().controlSize(.small) }
                }
            }

            ForEach(responses) { response in
                responseRow(response)
            }

            if allowsResponding {
                if !responses.isEmpty {
                    Divider()
                }
                HStack(alignment: .bottom, spacing: 8) {
                    Button {
                        mode = .voice
                        composerFocused = false
                        Task { await transcriber.toggle() }
                    } label: {
                        Image(systemName: transcriber.state == .listening ? "stop.fill" : "waveform")
                            .font(.headline)
                            .frame(width: 44, height: 44)
                            .background(
                                AppTheme.canvas,
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(transcriber.state == .listening ? "Stop voice response" : "Record voice response")

                    TextField("Response", text: $text, axis: .vertical)
                        .focused($composerFocused)
                        .lineLimit(1...5)
                        .font(.body)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(minHeight: 44)
                        .background(AppTheme.canvas, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(AppTheme.secondaryInk)
                        }
                        .onChange(of: text) { _, value in
                            if value.count > 600 { text = String(value.prefix(600)) }
                        }
                        .accessibilityLabel(mode == .voice ? "Voice response transcript" : "Text response")

                    Button { send() } label: {
                        Group {
                            if isSending {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "arrow.up")
                                    .font(.headline.weight(.bold))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(AppTheme.actionFill, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend || isSending)
                    .opacity(canSend && !isSending ? 1 : 0.45)
                    .accessibilityLabel("Send response")
                }

                if transcriber.state != .listening, let recordingURL = transcriber.recordingURL {
                    AudioBlessingPlayer(url: recordingURL)
                        .padding(.horizontal, 4)
                }

                if case let .failed(message) = transcriber.state {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.candle)
                } else if transcriber.state == .denied {
                    Label(
                        "Microphone or speech access is off. Enable it in Settings to record a response.",
                        systemImage: "mic.slash"
                    )
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryInk)
                }
            }
        }
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
                    .id(audioURL)
            } else if response.mode == .voice,
                      MediaRetentionPolicy.isExpired(submittedAt: response.submittedAt) {
                Label("Audio expired after 30 days", systemImage: "waveform.slash")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryInk)
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
