import SwiftUI
import UIKit
import AVFoundation
import PhotosUI

struct CaptureView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var mode: CaptureMode = .typed
    @State private var text = ""
    @State private var videoURL: URL?
    @State private var photoURL: URL?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showPhotoCamera = false
    @State private var showBiblePicker = false
    @State private var scriptureReference: ScriptureReference?
    @State private var isTranscribingVideo = false
    @State private var isRequestingCameraAccess = false
    @State private var isLoadingPhoto = false
    @State private var transcriber = SpeechTranscriber()
    @State private var repeatCandidates: [Blessing] = []
    @State private var repeatSource: Blessing?
    @State private var draftTarget: DailyPrompt?
    @State private var draftAuthorID: UUID?
    @State private var draftCreatedAt = Date.now
    @State private var draftExpiresAt: Date?
    @State private var draftInitialized = false
    @State private var isCheckpointingForSend = false
    @State private var wasSent = false
    @State private var checkpointTask: Task<Void, Never>?
    @State private var pendingRepeatRestoreID: UUID?
    @State private var restorationWarning: String?
    @FocusState private var editorFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        promptHeader
                        if repeatSource == nil {
                            repeatOptions
                            modePicker
                            captureArea
                            if mode != .video { photoAttachment }
                            scriptureTag
                        } else {
                            repeatedBlessingPreview
                        }
                        sendButton
                        if let error = model.draftSaveError {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .font(.footnote).foregroundStyle(AppTheme.missed)
                        }
                        if let restorationWarning { Text(restorationWarning).font(.footnote).foregroundStyle(AppTheme.missed) }
                    }
                    .frame(maxWidth: 680)
                    .padding(AppTheme.pagePadding)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Your blessing")
            .disabled(model.isSubmitting || isCheckpointingForSend)
            .interactiveDismissDisabled(model.isSubmitting || isCheckpointingForSend)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .disabled(model.isSubmitting || isCheckpointingForSend)
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                VideoCaptureView(
                    onCapture: { url in
                        videoURL = url
                        showCamera = false
                        text = ""
                        isTranscribingVideo = true
                        Task {
                            if let transcript = await transcriber.transcribeVideo(at: url) {
                                text = BlessingTextPolicy.limited(transcript)
                            }
                            isTranscribingVideo = false
                        }
                    },
                    onCancel: { showCamera = false },
                    onFailure: { message in
                        showCamera = false
                        model.message = message
                    }
                )
                .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $showPhotoCamera) {
                PhotoCaptureView(
                    onCapture: { url in
                        photoURL = url
                        showPhotoCamera = false
                    },
                    onCancel: { showPhotoCamera = false },
                    onFailure: { message in
                        showPhotoCamera = false
                        model.message = message
                    }
                )
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showBiblePicker) {
                BibleReferencePicker(selection: $scriptureReference)
            }
            .onChange(of: transcriber.transcript) { _, newValue in
                text = BlessingTextPolicy.limited(newValue)
            }
            .onChange(of: selectedPhotoItem) { _, item in
                guard let item else { return }
                Task { await loadPhoto(item) }
            }
            .onDisappear {
                checkpointTask?.cancel()
                transcriber.stop()
                if !wasSent { Task { _ = await saveDraftCheckpoint() } }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    transcriber.stop()
                    Task { _ = await saveDraftCheckpoint() }
                }
            }
            .background { checkpointObserver }
            .task { await runDraftSession() }
        }
    }

    private var checkpointObserver: some View {
        Color.clear
            .onChange(of: text) { _, _ in scheduleCheckpoint() }
            .onChange(of: mode) { _, _ in scheduleCheckpoint() }
            .onChange(of: photoURL) { _, _ in scheduleCheckpoint() }
            .onChange(of: videoURL) { _, _ in scheduleCheckpoint() }
            .onChange(of: scriptureReference) { _, _ in scheduleCheckpoint() }
            .onChange(of: transcriber.recordingURL) { _, _ in scheduleCheckpoint() }
            .onChange(of: transcriber.state) { _, _ in scheduleCheckpoint() }
    }

    private func runDraftSession() async {
        let restored = model.captureDraftToRestore
        if !draftInitialized {
            draftTarget = model.capturePrompt ?? model.prompt
            draftAuthorID = model.currentUser?.id
            draftCreatedAt = restored?.createdAt ?? Date.now
            draftExpiresAt = restored?.expiresAt ?? BlessingDraftPolicy.expiry(createdAt: draftCreatedAt,
                timeZoneIdentifier: model.circle?.timeZoneIdentifier ?? TimeZone.current.identifier)
            if let restored {
                mode = restored.mode
                text = restored.text
                scriptureReference = restored.scriptureReference
                pendingRepeatRestoreID = restored.repeatSourceID
                do {
                    // A live composer must survive deletion of its draft at midnight.
                    let editable = try await model.prepareDraftForEditing(restored)
                    guard !Task.isCancelled else { return }
                    photoURL = editable.photoURL
                    videoURL = editable.videoURL
                    transcriber.restoreDraftAudio(editable.audioSegments, text: restored.text)
                } catch {
                    restorationWarning = "Some draft media couldn’t be restored. Your text and Bible tag are kept; choose or record the missing media again."
                }
            }
            draftInitialized = true
        }
        repeatCandidates = await model.repeatBlessingCandidates()
        if let sourceID = pendingRepeatRestoreID {
            repeatSource = repeatCandidates.first { $0.id == sourceID }
            if repeatSource == nil { mode = .typed }
            pendingRepeatRestoreID = nil
        }
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(2)) } catch { break }
            _ = await saveDraftCheckpoint()
        }
    }

    @ViewBuilder
    private var repeatOptions: some View {
        if !repeatCandidates.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Reuse a recent blessing")
                    .font(.headline)
                Text("Available because it is still inside this circle’s reuse window.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryInk)
                ForEach(repeatCandidates) { blessing in
                    Button {
                        repeatSource = blessing
                        mode = blessing.captureMode
                        text = blessing.body ?? ""
                        scriptureReference = blessing.scriptureReference
                        photoURL = nil
                        videoURL = nil
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(sourceCircleName(for: blessing))
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(blessing.submittedAt, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.secondaryInk)
                            }
                            Text(blessing.body ?? "")
                                .font(.system(.subheadline, design: .serif))
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                            if let reference = blessing.scriptureReference {
                                Label(reference.displayName, systemImage: "book.closed")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.iris)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.canvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Reuses this blessing, attached media, and Bible verse in the current circle")
                }
            }
            .blessingCard()
        }
    }

    private var repeatedBlessingPreview: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Reusing your blessing", systemImage: "arrow.triangle.2.circlepath")
                    .font(.headline)
                    .foregroundStyle(AppTheme.primary)
                Spacer()
                Button("Choose another") {
                    repeatSource = nil
                    mode = .typed
                    text = ""
                    scriptureReference = nil
                }
                .font(.subheadline)
            }
            if let repeatSource {
                BlessingContentView(blessing: repeatSource, usesCard: false)
            }
            if let scriptureReference {
                Label(scriptureReference.displayName, systemImage: "book.closed")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.iris)
            }
            Text("This keeps your original format and attached media as a new blessing in \(model.circle?.name ?? "this circle"). Responses are not copied.")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryInk)
        }
        .blessingCard()
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
            Text(model.capturePrompt?.kind == .endOfDay ? "End your day with gratitude." : "Pause for what is good.")
                .font(.system(.title, design: .serif, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
            Text(
                model.capturePrompt?.kind == .endOfDay
                    ? "Share one final blessing from today. You can review it before sending."
                    : "Share one true thing from today. You can review it before sending."
            )
                .foregroundStyle(AppTheme.secondaryInk)
        }
    }

    private var modePicker: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            ForEach(CaptureMode.allCases) { option in
                Button {
                    if mode == .voice { transcriber.stop() }
                    mode = option
                    if option == .video {
                        photoURL = nil
                        selectedPhotoItem = nil
                    }
                    if option == .typed { editorFocused = true }
                } label: {
                    Label(option.title, systemImage: option.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(mode == option ? AppTheme.primary : AppTheme.surface)
                        .foregroundStyle(mode == option ? Color.white : AppTheme.ink)
                        .clipShape(Capsule())
                        .overlay { Capsule().stroke(AppTheme.divider, lineWidth: mode == option ? 0 : 1) }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(mode == option ? .isSelected : [])
            }
        }
    }

    private var photoAttachment: some View {
        let hasPhoto = photoURL != nil
        let cameraTitle = hasPhoto ? "Retake" : "Take photo"
        let libraryTitle = hasPhoto ? "Replace" : "Upload"
        let actionLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Photo", systemImage: "photo")
                    .font(.headline)
                Spacer()
                Text("Optional")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryInk)
            }

            if let photoURL, let image = UIImage(contentsOfFile: photoURL.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 480)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityLabel("Attached blessing photo")
            }

            actionLayout {
                Button {
                    Task { await openPhotoCamera() }
                } label: {
                    Label(cameraTitle, systemImage: "camera")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label(libraryTitle, systemImage: "photo.on.rectangle")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)

                if photoURL != nil {
                    Button("Remove", role: .destructive) {
                        photoURL = nil
                        selectedPhotoItem = nil
                    }
                    .frame(minHeight: 44)
                }

                if isLoadingPhoto { ProgressView().controlSize(.small) }
            }
        }
        .blessingCard()
    }

    @ViewBuilder
    private var captureArea: some View {
        switch mode {
        case .typed:
            editor(title: "Write your blessing", footer: "\(BlessingTextPolicy.length(of: text)) of \(BlessingTextPolicy.maximumLength) characters")
        case .voice:
            VStack(spacing: 18) {
                editor(title: "Your words appear here", footer: speechFooter)
                if transcriber.state != .listening, let recordingURL = transcriber.recordingURL {
                    AudioBlessingPlayer(url: recordingURL)
                        .padding(14)
                        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(AppTheme.divider)
                        }
                }
                Button {
                    Task { await transcriber.toggle(existingTranscript: text) }
                } label: {
                    Label(
                        transcriber.state == .listening ? "Pause recording" : (transcriber.recordingURL == nil ? "Start listening" : "Continue recording"),
                        systemImage: transcriber.state == .listening ? "stop.fill" : "waveform"
                    )
                    .frame(maxWidth: .infinity, minHeight: AppTheme.controlHeight)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(transcriber.state == .requestingPermission || transcriber.state == .finishing)
                if transcriber.recordingURL != nil {
                    Button("Start over", role: .destructive) { transcriber.reset(); text = "" }
                        .frame(minHeight: 44).disabled(transcriber.state == .finishing)
                }
            }
        case .video:
            VStack(spacing: 18) {
                Group {
                    if let videoURL {
                        VideoBlessingPlayer(url: videoURL)
                    } else {
                        RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                            .fill(AppTheme.surface)
                            .overlay {
                        VStack(spacing: 12) {
                            Image(systemName: "video.badge.plus")
                                .font(.system(size: 44, weight: .light))
                                .foregroundStyle(AppTheme.dawn)
                                .accessibilityHidden(true)
                            Text("Record up to 30 seconds")
                                .font(.headline)
                            Text("You’ll review it here before sending.")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.secondaryInk)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                    }
                    }
                }
                .frame(minHeight: 260)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))

                Button {
                    Task { await openCamera() }
                } label: {
                    HStack {
                        Label(videoURL == nil ? "Open camera" : "Record again", systemImage: "camera")
                        if isRequestingCameraAccess { ProgressView() }
                    }
                        .frame(maxWidth: .infinity, minHeight: AppTheme.controlHeight)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isRequestingCameraAccess)

                if videoURL != nil {
                    if isTranscribingVideo {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Creating an editable transcript…")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.secondaryInk)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    editor(
                        title: "Video transcript",
                        footer: isTranscribingVideo
                            ? "Listening to your video…"
                            : "Review or edit the transcript before sending. \(BlessingTextPolicy.length(of: text)) of \(BlessingTextPolicy.maximumLength) characters"
                    )
                }
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
                    let limited = BlessingTextPolicy.limited(newValue)
                    if limited != newValue { text = limited }
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
        case .finishing: "Combining your recording segments…"
        case .listening: "Listening… tap Stop listening when you’re done."
        case .denied: "Speech access is off. Enable it in Settings or choose Type."
        case let .failed(message): message
        }
    }

    private var sendButton: some View {
        Button {
            Task {
                isCheckpointingForSend = true
                checkpointTask?.cancel()
                defer { isCheckpointingForSend = false }
                let audio = await transcriber.finishRecording()
                guard await saveDraftCheckpoint(evenWhileSending: true) else { return }
                let succeeded: Bool
                if let repeatSource {
                    succeeded = await model.repeatBlessing(repeatSource)
                } else {
                    succeeded = await model.submit(
                        mode: mode,
                        body: text,
                        audioURL: mode == .voice ? audio : nil,
                        videoURL: videoURL,
                        photoURL: mode == .video ? nil : photoURL,
                        scriptureReference: scriptureReference
                    )
                }
                if succeeded {
                    wasSent = true
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
        .buttonStyle(MannaPrimaryButtonStyle())
        .tint(AppTheme.actionFill)
        .controlSize(.large)
        .disabled(model.isSubmitting || isCheckpointingForSend || !draftInitialized || !canSubmit)
        .disabled(transcriber.state == .finishing || transcriber.state == .requestingPermission)
    }

    private func scheduleCheckpoint() {
        guard draftInitialized, !wasSent, !isCheckpointingForSend, !model.isSubmitting else { return }
        checkpointTask?.cancel()
        checkpointTask = Task {
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            _ = await saveDraftCheckpoint()
        }
    }

    private func saveDraftCheckpoint(evenWhileSending: Bool = false) async -> Bool {
        guard draftInitialized, !wasSent,
              evenWhileSending || (!model.isSubmitting && !isCheckpointingForSend),
              let target = draftTarget, let authorID = draftAuthorID, let expiry = draftExpiresAt else { return true }
        let draft = BlessingDraft(authorID: authorID, circleID: target.circleID, promptID: target.id,
            createdAt: draftCreatedAt, expiresAt: expiry, updatedAt: .now, mode: mode, text: text,
            audioSegments: mode == .voice && repeatSource == nil ? transcriber.draftAudioSegments : [],
            videoURL: mode == .video && repeatSource == nil ? videoURL : nil,
            photoURL: mode != .video && repeatSource == nil ? photoURL : nil,
            scriptureReference: scriptureReference, repeatSourceID: repeatSource?.id)
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Save blessing draft")
        defer { if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) } }
        return await model.persistDraft(draft)
    }

    private var canSubmit: Bool {
        if repeatSource != nil { return true }
        guard (try? BlessingTextPolicy.validated(text)) != nil else { return false }
        return switch mode {
        case .typed: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .voice:
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && transcriber.recordingURL != nil
                && transcriber.state != .listening
        case .video:
            videoURL != nil
                && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !isTranscribingVideo
        }
    }

    private func sourceCircleName(for blessing: Blessing) -> String {
        model.circles.first(where: { $0.id == blessing.circleID })?.name ?? "Another circle"
    }

    private func openCamera() async {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            model.message = BlessingError.cameraUnavailable.localizedDescription
            return
        }
        guard UIImagePickerController.availableMediaTypes(for: .camera)?.contains(UTType.movie.identifier) == true else {
            model.message = "This device's camera is not available for video recording."
            return
        }
        isRequestingCameraAccess = true
        defer { isRequestingCameraAccess = false }

        let cameraAllowed: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraAllowed = true
        case .notDetermined:
            cameraAllowed = await MediaAuthorization.requestCameraAccess()
        default:
            cameraAllowed = false
        }
        let microphoneAllowed = await AVAudioApplication.requestRecordPermission()
        guard cameraAllowed, microphoneAllowed else {
            model.message = "Camera and microphone access are required for a video blessing. Enable them in Settings and try again."
            return
        }
        showCamera = true
    }

    private func openPhotoCamera() async {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            model.message = BlessingError.cameraUnavailable.localizedDescription
            return
        }
        let allowed: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: allowed = true
        case .notDetermined: allowed = await MediaAuthorization.requestCameraAccess()
        default: allowed = false
        }
        guard allowed else {
            model.message = "Camera access is required to take a photo. Enable it in Settings or upload one from Photos."
            return
        }
        showPhotoCamera = true
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        isLoadingPhoto = true
        defer { isLoadingPhoto = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                model.message = "The selected photo could not be loaded. Choose another photo."
                return
            }
            photoURL = try CaptureMediaStore.persistPhoto(data: data)
        } catch {
            model.message = "The selected photo could not be saved. Choose another photo."
        }
    }
}
