import AVKit
import SwiftUI

struct CircleTimelineView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: BlessingSelection?

    var body: some View {
        ZStack {
            AppTheme.canvas.ignoresSafeArea()
            if model.lanes.isEmpty {
                ContentUnavailableView(
                    "No days yet",
                    systemImage: "clock",
                    description: Text("Your circle’s blessings will gather here.")
                )
            } else {
                ScrollView([.horizontal, .vertical]) {
                    HStack(alignment: .top, spacing: 20) {
                        ForEach(model.lanes) { lane in
                            TimelineLaneView(
                                lane: lane,
                                isCurrentUser: lane.member.id == model.currentUser?.id,
                                onSelect: { blessing in
                                    selection = BlessingSelection(member: lane.member, blessing: blessing)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, AppTheme.pagePadding)
                    .padding(.vertical, 18)
                    .padding(.bottom, 100)
                }
                .scrollIndicators(.visible)
            }
        }
        .navigationTitle("Timeline")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { try? await model.refreshTimeline() }
        .sheet(item: $selection) { selection in
            BlessingDetailView(member: selection.member, blessing: selection.blessing)
        }
    }
}

private struct BlessingSelection: Identifiable {
    let member: Member
    let blessing: Blessing
    var id: UUID { blessing.id }
}

private struct TimelineLaneView: View {
    let lane: TimelineLane
    let isCurrentUser: Bool
    let onSelect: (Blessing) -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                AvatarBadge(member: lane.member, size: 52)
                Text(isCurrentUser ? "You" : lane.member.displayName)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
            }
            .padding(.bottom, 20)

            ForEach(Array(lane.events.enumerated()), id: \.element.id) { index, event in
                TimelineEventView(
                    event: event,
                    isLast: index == lane.events.count - 1,
                    onSelect: onSelect
                )
            }
        }
        .frame(width: 238)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(isCurrentUser ? "Your" : lane.member.displayName + "’s") timeline")
    }
}

private struct TimelineEventView: View {
    let event: TimelineEvent
    let isLast: Bool
    let onSelect: (Blessing) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                marker
                    .frame(width: 24, height: 24)
                if !isLast {
                    Rectangle()
                        .fill(AppTheme.divider)
                        .frame(width: 2, height: 184)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(event.date.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryInk)
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.bottom, isLast ? 0 : 22)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var marker: some View {
        switch event.status {
        case .blessing:
            Circle()
                .fill(AppTheme.iris)
                .overlay { Circle().stroke(AppTheme.surface, lineWidth: 5) }
        case .missed:
            Circle()
                .stroke(AppTheme.missed, style: StrokeStyle(lineWidth: 3, dash: [3, 3]))
                .padding(3)
        case .locked:
            Image(systemName: "lock.fill")
                .font(.caption)
                .foregroundStyle(AppTheme.candle)
                .background(Circle().fill(AppTheme.surface).frame(width: 24, height: 24))
        case .waiting:
            Circle()
                .stroke(AppTheme.dawn, lineWidth: 2)
                .padding(4)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch event.status {
        case let .blessing(blessing):
            Button { onSelect(blessing) } label: {
                VStack(alignment: .leading, spacing: 8) {
                    if blessing.captureMode != .typed {
                        Label(
                            blessing.captureMode == .video ? "Video" : "Voice",
                            systemImage: blessing.captureMode == .video ? "play.rectangle.fill" : "waveform"
                        )
                        .font(.caption.weight(.semibold))
                    }
                    Text(blessing.body ?? "")
                        .font(.system(.subheadline, design: .serif))
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 8) {
                        Text(blessing.submittedAt, style: .time)
                            .font(.caption2)
                            .foregroundStyle(AppTheme.secondaryInk)
                        if blessing.isLate {
                            Label("Late", systemImage: "clock.badge.exclamationmark")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppTheme.candle)
                        }
                    }
                    if let reference = blessing.scriptureReference {
                        Label(reference.displayName, systemImage: "book.closed")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.iris)
                            .lineLimit(1)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppTheme.secondaryInk)
                        .padding(10)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the complete blessing")
        case .missed:
            Label("Missed this day", systemImage: "minus.circle")
                .font(.subheadline)
                .foregroundStyle(AppTheme.missed)
                .padding(.vertical, 10)
        case .locked:
            VStack(alignment: .leading, spacing: 5) {
                Label("Today is hidden", systemImage: "lock.fill")
                    .font(.subheadline.weight(.semibold))
                Text("Share yours to open it.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryInk)
            }
            .padding(14)
            .background(AppTheme.candle.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        case .waiting:
            Label("Still time to share", systemImage: "hourglass")
                .font(.subheadline)
                .foregroundStyle(AppTheme.dawn)
                .padding(.vertical, 10)
        }
    }
}

private struct BlessingDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let member: Member
    let blessing: Blessing
    @State private var videoPlayer: AVPlayer?

    init(member: Member, blessing: Blessing) {
        self.member = member
        self.blessing = blessing
        _videoPlayer = State(initialValue: blessing.videoURL.map { AVPlayer(url: $0) })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        blessingContent
                        if let reference = blessing.scriptureReference {
                            ScripturePassageView(reference: reference)
                        }
                    }
                    .frame(maxWidth: 680)
                    .padding(AppTheme.pagePadding)
                    .padding(.bottom, 40)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Blessing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onDisappear { videoPlayer?.pause() }
        }
        .presentationDetents([.large])
    }

    private var header: some View {
        HStack(spacing: 12) {
            AvatarBadge(member: member, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(member.displayName)
                    .font(.headline)
                Text(blessing.submittedAt.formatted(date: .long, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryInk)
            }
            Spacer()
            if blessing.isLate {
                Label("Late", systemImage: "clock.badge.exclamationmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.candle)
            }
        }
    }

    @ViewBuilder
    private var blessingContent: some View {
        switch blessing.captureMode {
        case .typed:
            VStack(alignment: .leading, spacing: 10) {
                Text("Reflection")
                    .font(.headline)
                Text(blessing.body ?? "")
                    .font(.system(.title3, design: .serif))
                    .textSelection(.enabled)
            }
            .blessingCard()
        case .voice:
            VStack(alignment: .leading, spacing: 16) {
                if let audioURL = blessing.audioURL {
                    AudioBlessingPlayer(url: audioURL)
                } else {
                    Label("Audio is unavailable", systemImage: "waveform.slash")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryInk)
                }
                Divider()
                Text("Transcript")
                    .font(.headline)
                Text(blessing.body ?? "")
                    .font(.system(.body, design: .serif))
                    .textSelection(.enabled)
            }
            .blessingCard()
        case .video:
            VStack(alignment: .leading, spacing: 16) {
                if let videoPlayer {
                    VideoPlayer(player: videoPlayer)
                        .frame(minHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    ContentUnavailableView("Video unavailable", systemImage: "video.slash")
                }
                Divider()
                Text("Transcript")
                    .font(.headline)
                Text(blessing.body ?? "")
                    .font(.system(.body, design: .serif))
                    .textSelection(.enabled)
            }
            .blessingCard()
        }
    }
}

private struct AudioBlessingPlayer: View {
    @State private var player: AVPlayer
    @State private var isPlaying = false

    init(url: URL) {
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        Button {
            if isPlaying {
                player.pause()
            } else {
                player.play()
            }
            isPlaying.toggle()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 36))
                VStack(alignment: .leading, spacing: 3) {
                    Text(isPlaying ? "Pause recording" : "Play recording")
                        .font(.headline)
                    Text("Voice blessing")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryInk)
                }
                Spacer()
                Image(systemName: "waveform")
                    .foregroundStyle(AppTheme.iris)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDisappear { player.pause() }
    }
}

private struct ScripturePassageView: View {
    @Environment(AppModel.self) private var model
    let reference: ScriptureReference
    @State private var text: String?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(reference.displayName, systemImage: "book.closed.fill")
                .font(.headline)
                .foregroundStyle(AppTheme.iris)
            if let text {
                Text(text)
                    .font(.system(.body, design: .serif))
                    .textSelection(.enabled)
                Text(model.selectedBibleTranslation.shortName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryInk)
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryInk)
                Button("Try again") { Task { await loadPassage() } }
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading in \(model.selectedBibleTranslation.shortName)…")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryInk)
                }
            }
        }
        .blessingCard()
        .task(id: "\(reference.displayName)-\(model.selectedBibleTranslation.id)") {
            await loadPassage()
        }
    }

    private func loadPassage() async {
        text = nil
        errorMessage = nil
        do {
            text = try await model.scriptureText(for: reference)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "The verse could not be loaded. Check your connection and try again."
        }
    }
}

struct AvatarBadge: View {
    let member: Member
    let size: CGFloat

    var body: some View {
        Text(member.initials)
            .font(.system(size: size * 0.31, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(avatarColor, in: Circle())
            .accessibilityLabel(member.displayName)
    }

    private var avatarColor: Color {
        [AppTheme.iris, AppTheme.dawn, AppTheme.candle][abs(member.tintSeed) % 3]
    }
}
