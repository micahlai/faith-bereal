import SwiftUI
import UIKit

struct CaptureView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var mode: CaptureMode = .typed
    @State private var text = ""
    @State private var videoURL: URL?
    @State private var showCamera = false
    @State private var showBiblePicker = false
    @State private var scriptureReference: ScriptureReference?
    @State private var transcriber = SpeechTranscriber()
    @FocusState private var editorFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        promptHeader
                        modePicker
                        captureArea
                        scriptureTag
                        sendButton
                    }
                    .frame(maxWidth: 680)
                    .padding(AppTheme.pagePadding)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Your blessing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .disabled(model.isSubmitting)
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                VideoCaptureView(
                    onCapture: { url in
                        videoURL = url
                        showCamera = false
                    },
                    onCancel: { showCamera = false }
                )
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showBiblePicker) {
                BibleReferencePicker(selection: $scriptureReference)
            }
            .onChange(of: transcriber.transcript) { _, newValue in
                text = newValue
            }
            .onDisappear { transcriber.stop() }
        }
    }

    private var scriptureTag: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "book.closed")
                    .font(.title3)
                    .foregroundStyle(AppTheme.iris)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(scriptureReference?.displayName ?? "Tag a Bible verse")
                        .font(.headline)
                    Text(
                        scriptureReference == nil
                            ? "Optional. Preview it before adding it to your blessing."
                            : "Shown to each person in their chosen Bible version."
                    )
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryInk)
                }
                Spacer()
            }

            HStack(spacing: 12) {
                Button(scriptureReference == nil ? "Choose a verse" : "Change verse") {
                    showBiblePicker = true
                }
                .buttonStyle(.bordered)
                if scriptureReference != nil {
                    Button("Remove", role: .destructive) { scriptureReference = nil }
                        .buttonStyle(.borderless)
                }
            }
        }
        .blessingCard()
    }

    private var promptHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pause for what is good.")
                .font(.system(.title, design: .serif, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
            Text("Share one true thing from today. You can review it before sending.")
                .foregroundStyle(AppTheme.secondaryInk)
        }
    }

    private var modePicker: some View {
        HStack(spacing: 8) {
            ForEach(CaptureMode.allCases) { option in
                Button {
                    if mode == .voice { transcriber.stop() }
                    mode = option
                    if option == .typed { editorFocused = true }
                } label: {
                    Label(option.title, systemImage: option.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(mode == option ? AppTheme.iris : AppTheme.surface)
                        .foregroundStyle(mode == option ? Color.white : AppTheme.ink)
                        .clipShape(Capsule())
                        .overlay { Capsule().stroke(AppTheme.divider, lineWidth: mode == option ? 0 : 1) }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(mode == option ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private var captureArea: some View {
        switch mode {
        case .typed:
            editor(title: "Write your blessing", footer: "\(text.count) of 600 characters")
        case .voice:
            VStack(spacing: 18) {
                editor(title: "Your words appear here", footer: speechFooter)
                Button {
                    Task { await transcriber.toggle() }
                } label: {
                    Label(
                        transcriber.state == .listening ? "Stop listening" : "Start listening",
                        systemImage: transcriber.state == .listening ? "stop.fill" : "waveform"
                    )
                    .frame(maxWidth: .infinity, minHeight: AppTheme.controlHeight)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        case .video:
            VStack(spacing: 18) {
                RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                    .fill(AppTheme.surface)
                    .frame(height: 260)
                    .overlay {
                        VStack(spacing: 12) {
                            Image(systemName: videoURL == nil ? "video.badge.plus" : "checkmark.circle.fill")
                                .font(.system(size: 44, weight: .light))
                                .foregroundStyle(videoURL == nil ? AppTheme.dawn : AppTheme.iris)
                                .accessibilityHidden(true)
                            Text(videoURL == nil ? "Record up to 30 seconds" : "Video ready")
                                .font(.headline)
                            Text(videoURL == nil ? "You’ll review it here before sending." : "Record again if you want another take.")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.secondaryInk)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                    }
                Button {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        showCamera = true
                    } else {
                        model.message = BlessingError.cameraUnavailable.localizedDescription
                    }
                } label: {
                    Label(videoURL == nil ? "Open camera" : "Record again", systemImage: "camera")
                        .frame(maxWidth: .infinity, minHeight: AppTheme.controlHeight)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    private func editor(title: String, footer: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            TextEditor(text: $text)
                .focused($editorFocused)
                .font(.system(.body, design: .serif))
                .frame(minHeight: 190)
                .padding(10)
                .scrollContentBackground(.hidden)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1) }
                .onChange(of: text) { _, newValue in
                    if newValue.count > 600 { text = String(newValue.prefix(600)) }
                }
                .accessibilityLabel(title)
            Text(footer)
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryInk)
        }
    }

    private var speechFooter: String {
        switch transcriber.state {
        case .idle: "Tap Start listening, then speak naturally."
        case .requestingPermission: "Requesting microphone and speech access…"
        case .listening: "Listening… tap Stop listening when you’re done."
        case .denied: "Speech access is off. Enable it in Settings or choose Type."
        case let .failed(message): message
        }
    }

    private var sendButton: some View {
        Button {
            Task {
                transcriber.stop()
                if await model.submit(
                    mode: mode,
                    body: text,
                    videoURL: videoURL,
                    scriptureReference: scriptureReference
                ) {
                    dismiss()
                }
            }
        } label: {
            Group {
                if model.isSubmitting {
                    ProgressView().tint(.white)
                } else {
                    Label("Send blessing", systemImage: "paperplane.fill")
                }
            }
            .frame(maxWidth: .infinity, minHeight: AppTheme.controlHeight)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(model.isSubmitting || !canSubmit)
    }

    private var canSubmit: Bool {
        switch mode {
        case .typed, .voice: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .video: videoURL != nil
        }
    }
}
