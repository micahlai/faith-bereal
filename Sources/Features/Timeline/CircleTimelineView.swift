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
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            Grid(alignment: .topLeading, horizontalSpacing: 20, verticalSpacing: 0) {
                                ForEach(TimelineRow.rows(for: model.lanes)) { row in
                                    TimelineDayRow(
                                        row: row,
                                        lanes: model.lanes,
                                        onSelect: { member, blessing in
                                            selection = BlessingSelection(member: member, blessing: blessing)
                                        }
                                    )
                                }
                            }
                        } header: {
                            TimelineMemberHeader(
                                lanes: model.lanes,
                                currentUserID: model.currentUser?.id
                            )
                        }
                    }
                    .padding(.horizontal, AppTheme.pagePadding)
                    .padding(.bottom, 118)
                }
                .scrollIndicators(.visible)
            }
        }
        .navigationTitle("Timeline")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppTheme.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .refreshable { try? await model.refreshTimeline() }
        .sheet(item: $selection) { selection in
            BlessingDetailView(
                member: selection.member,
                blessing: selection.blessing,
                allowsResponses: model.canRespond(to: selection.blessing)
            )
        }
    }
}

private struct BlessingSelection: Identifiable {
    let member: Member
    let blessing: Blessing
    var id: UUID { blessing.id }
}

private struct TimelineMemberHeader: View {
    let lanes: [TimelineLane]
    let currentUserID: UUID?

    var body: some View {
        Grid(alignment: .bottomLeading, horizontalSpacing: 20) {
            GridRow(alignment: .bottom) {
                Color.clear
                    .frame(width: 72, height: 1)
                    .accessibilityHidden(true)
                ForEach(lanes) { lane in
                    VStack(spacing: 8) {
                        AvatarBadge(member: lane.member, size: 48)
                        Text(lane.member.id == currentUserID ? "You" : lane.member.displayName)
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink)
                            .lineLimit(1)
                    }
                    .frame(width: 238)
                }
            }
        }
        .padding(.vertical, 12)
        .background(AppTheme.canvas)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityIdentifier("timeline.memberHeader")
        .zIndex(2)
    }
}

private struct TimelineRow: Identifiable {
    enum Kind: Int {
        case prompt
        case joined
    }

    let day: Date
    let kind: Kind
    let eventsByMemberID: [UUID: TimelineEvent]

    var id: String { "\(day.timeIntervalSinceReferenceDate)-\(kind.rawValue)" }

    static func rows(for lanes: [TimelineLane], calendar: Calendar = .current) -> [TimelineRow] {
        var promptRows: [Date: [UUID: TimelineEvent]] = [:]
        var joinedRows: [Date: [UUID: TimelineEvent]] = [:]

        for lane in lanes {
            for event in lane.events {
                let day = calendar.startOfDay(for: event.date)
                if case .joinedCircle = event.status {
                    joinedRows[day, default: [:]][lane.member.id] = event
                } else {
                    promptRows[day, default: [:]][lane.member.id] = event
                }
            }
        }

        let prompts = promptRows.map {
            TimelineRow(day: $0.key, kind: .prompt, eventsByMemberID: $0.value)
        }
        let joins = joinedRows.map {
            TimelineRow(day: $0.key, kind: .joined, eventsByMemberID: $0.value)
        }
        return (prompts + joins).sorted { lhs, rhs in
            if lhs.day != rhs.day { return lhs.day > rhs.day }
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
    }
}

private struct TimelineDayRow: View {
    let row: TimelineRow
    let lanes: [TimelineLane]
    let onSelect: (Member, Blessing) -> Void

    var body: some View {
        GridRow(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.day.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryInk)
                if row.kind == .joined {
                    Text("Joined")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.iris)
                }
            }
            .frame(width: 72, alignment: .leading)
            .padding(.top, 3)

            ForEach(lanes) { lane in
                if let event = row.eventsByMemberID[lane.member.id] {
                    TimelineEventView(
                        event: event,
                        onSelect: { blessing in onSelect(lane.member, blessing) }
                    )
                    .frame(width: 238)
                    .frame(maxHeight: .infinity, alignment: .top)
                } else {
                    TimelineConnectorView(
                        isVisible: row.day >= Calendar.current.startOfDay(for: lane.member.joinedAt)
                    )
                    .frame(width: 238)
                    .frame(minHeight: 42, maxHeight: .infinity, alignment: .top)
                }
            }
        }
    }
}

private struct TimelineConnectorView: View {
    let isVisible: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Rectangle()
                .fill(isVisible ? AppTheme.divider : .clear)
                .frame(width: 2)
                .frame(maxHeight: .infinity)
                .padding(.leading, 11)
            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)
    }
}

private struct TimelineEventView: View {
    let event: TimelineEvent
    let onSelect: (Blessing) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                marker
                    .frame(width: 24, height: 24)
                if !isJoinedMarker {
                    Rectangle()
                        .fill(AppTheme.divider)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.bottom, isJoinedMarker ? 12 : 22)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .combine)
    }

    private var isJoinedMarker: Bool {
        if case .joinedCircle = event.status { return true }
        return false
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
        case .joinedCircle:
            Image(systemName: "person.badge.plus")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.iris)
                .background(Circle().fill(AppTheme.surface).frame(width: 24, height: 24))
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
                        .lineLimit(15)
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
                    TimelineResponderAvatars(blessing: blessing)
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
        case .joinedCircle:
            VStack(alignment: .leading, spacing: 4) {
                Text("Joined circle")
                    .font(.subheadline.weight(.semibold))
                Text(event.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryInk)
            }
            .padding(.vertical, 10)
        }
    }
}

private struct TimelineResponderAvatars: View {
    @Environment(AppModel.self) private var model
    let blessing: Blessing
    @State private var responderIDs: [UUID] = []

    var body: some View {
        Group {
            if !responders.isEmpty {
                HStack(spacing: -6) {
                    ForEach(responders.prefix(5)) { member in
                        AvatarBadge(member: member, size: 24)
                            .overlay { Circle().stroke(AppTheme.surface, lineWidth: 2) }
                    }
                    if responders.count > 5 {
                        Text("+\(responders.count - 5)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryInk)
                            .padding(.leading, 10)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(responseAccessibilityLabel)
            }
        }
        .task(id: blessing.id) { await loadResponses() }
    }

    private var responders: [Member] {
        let members = model.circle?.members ?? []
        return responderIDs.compactMap { id in members.first(where: { $0.id == id }) }
    }

    private var responseAccessibilityLabel: String {
        let names = responders.map(\.displayName)
        return names.isEmpty ? "No responses" : "Responses from \(names.joined(separator: ", "))"
    }

    private func loadResponses() async {
        let responses = await model.responses(for: blessing)
        var seen = Set<UUID>()
        responderIDs = responses.map(\.authorID).filter { seen.insert($0).inserted }
    }
}

struct BlessingDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let member: Member
    let blessing: Blessing
    let allowsResponses: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        BlessingContentView(blessing: blessing)
                            .id(blessing.id)
                        BlessingResponsesView(blessing: blessing, allowsResponding: allowsResponses)
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

}

struct BlessingContentView: View {
    let blessing: Blessing
    @State private var videoPlayer: AVPlayer?

    init(blessing: Blessing) {
        self.blessing = blessing
        _videoPlayer = State(initialValue: blessing.videoURL.map { AVPlayer(url: $0) })
    }

    var body: some View {
        Group {
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
        .onDisappear { videoPlayer?.pause() }
    }
}

struct AudioBlessingPlayer: View {
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

struct ScripturePassageView: View {
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
