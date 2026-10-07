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
                                ForEach(TimelineRow.rows(for: model.lanes, calendar: circleCalendar)) { row in
                                    TimelineDayRow(
                                        row: row,
                                        lanes: model.lanes,
                                        calendar: circleCalendar,
                                        currentUserID: model.currentUser?.id,
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
        .refreshable { await model.refreshCurrentCircle() }
        .sheet(item: $selection) { selection in
            BlessingDetailView(
                member: selection.member,
                blessing: selection.blessing,
                allowsResponses: model.canRespond(to: selection.blessing)
            )
        }
    }

    private var circleCalendar: Calendar {
        CircleLocalDay.calendar(timeZoneIdentifier: model.circle?.timeZoneIdentifier ?? TimeZone.current.identifier)
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
    let calendar: Calendar
    let currentUserID: UUID?
    let onSelect: (Member, Blessing) -> Void

    var body: some View {
        GridRow(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dayLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryInk)
                if row.kind == .joined {
                    Text("Joined")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.primary)
                }
            }
            .frame(width: 72, alignment: .leading)
            .padding(.top, 3)

            ForEach(lanes) { lane in
                if let event = row.eventsByMemberID[lane.member.id] {
                    TimelineEventView(
                        event: event,
                        member: lane.member,
                        currentUserID: currentUserID,
                        onSelect: { blessing in onSelect(lane.member, blessing) }
                    )
                    .frame(width: 238)
                    .frame(maxHeight: .infinity, alignment: .top)
                } else {
                    TimelineConnectorView(
                        isVisible: row.day >= calendar.startOfDay(for: lane.member.joinedAt)
                    )
                    .frame(width: 238)
                    .frame(minHeight: 42, maxHeight: .infinity, alignment: .top)
                }
            }
        }
    }

    private var dayLabel: String {
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        style.timeZone = calendar.timeZone
        return row.day.formatted(style)
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
    let member: Member
    let currentUserID: UUID?
    let onSelect: (Blessing) -> Void
    @State private var isBodyTruncated = false

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
                .fill(AppTheme.primary)
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
                .foregroundStyle(AppTheme.primary)
                .background(Circle().fill(AppTheme.surface).frame(width: 24, height: 24))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch event.status {
        case let .blessing(blessing):
            Button { onSelect(blessing) } label: {
                VStack(alignment: .leading, spacing: 8) {
                    if blessing.captureMode != .typed || blessing.photoURL != nil {
                        HStack(spacing: 10) {
                            if blessing.captureMode != .typed {
                                Label(
                                    blessing.captureMode == .video ? "Video" : "Voice",
                                    systemImage: blessing.captureMode == .video ? "play.rectangle.fill" : "waveform"
                                )
                            }
                            if blessing.photoURL != nil {
                                Label("Photo", systemImage: "photo.fill")
                            }
                        }
                        .font(.caption.weight(.semibold))
                    }
                    TruncationAwareText(
                        text: blessing.body ?? "",
                        lineLimit: 15,
                        font: .system(.subheadline, design: .serif),
                        isTruncated: $isBodyTruncated
                    )
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
                    if isBodyTruncated {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppTheme.secondaryInk)
                            .padding(10)
                            .accessibilityHidden(true)
                    }
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
                Label("Locked until you share", systemImage: "lock.fill")
                    .font(.subheadline.weight(.semibold))
                Text("Share yours to reveal today’s peer updates.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryInk)
            }
            .padding(14)
            .background(AppTheme.candle.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        case .waiting:
            Label(
                member.id == currentUserID
                    ? "You can still share"
                    : "\(member.displayName) can still share",
                systemImage: "hourglass"
            )
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
    @Environment(AppModel.self) private var model
    let member: Member
    let allowsResponses: Bool
    @State private var blessing: Blessing
    @State private var isEditing = false

    init(member: Member, blessing: Blessing, allowsResponses: Bool) {
        self.member = member
        self.allowsResponses = allowsResponses
        _blessing = State(initialValue: blessing)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        BlessingContentView(blessing: blessing)
                            .id(blessing.id)
                        if let reference = blessing.scriptureReference {
                            ScripturePassageView(reference: reference)
                        }
                        BlessingResponsesView(blessing: blessing, allowsResponding: allowsResponses)
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
                ToolbarItem(placement: .topBarTrailing) {
                    SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { context in
                        HStack(spacing: 6) {
                            if model.canEdit(blessing, at: context.date) {
                                Button("Edit") { isEditing = true }
                            }
                            Button { dismiss() } label: {
                                Image(systemName: "xmark")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(width: 32, height: 32)
                                    .background(AppTheme.surface, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                            .accessibilityLabel("Close blessing")
                        }
                        .fixedSize()
                    }
                }
            }
        }
        .presentationDetents([.large])
        .sheet(isPresented: $isEditing) {
            BlessingEditView(blessing: blessing) { updated in
                blessing = updated
            }
        }
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
                if blessing.editedAt != nil {
                    Text("Edited")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryInk)
                }
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

struct BlessingEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    let blessing: Blessing
    let onSaved: (Blessing) -> Void

    @State private var bodyText: String
    @State private var scriptureReference: ScriptureReference?
    @State private var showingBiblePicker = false
    @State private var isSaving = false

    init(blessing: Blessing, onSaved: @escaping (Blessing) -> Void) {
        self.blessing = blessing
        self.onSaved = onSaved
        _bodyText = State(initialValue: blessing.body ?? "")
        _scriptureReference = State(initialValue: blessing.scriptureReference)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(blessing.captureMode == .typed ? "Blessing" : "Transcript") {
                    TextEditor(text: $bodyText)
                        .frame(minHeight: 180)
                        .accessibilityLabel(blessing.captureMode == .typed ? "Blessing text" : "Blessing transcript")
                    Text("\(bodyText.count)/600")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(bodyText.count > 600 ? Color.red : AppTheme.secondaryInk)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                Section("Bible verse") {
                    Button {
                        showingBiblePicker = true
                    } label: {
                        HStack {
                            Label(
                                scriptureReference?.displayName ?? "Tag a Bible verse",
                                systemImage: "book.closed"
                            )
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.secondaryInk)
                        }
                    }
                    if scriptureReference != nil {
                        Button("Remove Bible verse", role: .destructive) {
                            scriptureReference = nil
                        }
                    }
                }

                if blessing.captureMode != .typed || blessing.photoURL != nil {
                    Section {
                        Text("Your original media stays attached to this blessing.")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.secondaryInk)
                    }
                }
            }
            .navigationTitle("Edit blessing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        Task { await save() }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
            .sheet(isPresented: $showingBiblePicker) {
                BibleReferencePicker(selection: $scriptureReference)
            }
        }
        .interactiveDismissDisabled(isSaving)
    }

    private var canSave: Bool {
        let trimmed = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        return (1...600).contains(trimmed.count)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        guard let updated = await model.updateBlessing(
            blessing,
            body: bodyText,
            scriptureReference: scriptureReference
        ) else { return }
        onSaved(updated)
        dismiss()
    }
}

struct BlessingContentView: View {
    let blessing: Blessing
    var usesCard = true

    var body: some View {
        if usesCard {
            content.blessingCard()
        } else {
            content
        }
    }

    @ViewBuilder private var content: some View {
        Group {
            switch blessing.captureMode {
            case .typed:
                VStack(alignment: .leading, spacing: 10) {
                    if let photoURL = blessing.photoURL {
                        BlessingPhotoView(url: photoURL)
                    }
                    Text(blessing.body ?? "")
                        .font(.system(.title3, design: .serif))
                        .textSelection(.enabled)
                }
            case .voice:
                VStack(alignment: .leading, spacing: 16) {
                    if let audioURL = blessing.audioURL {
                        AudioBlessingPlayer(url: audioURL)
                    } else {
                        Label("Audio is unavailable", systemImage: "waveform.slash")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryInk)
                    }
                    if let photoURL = blessing.photoURL {
                        BlessingPhotoView(url: photoURL)
                    }
                    Text(blessing.body ?? "")
                        .font(.system(.body, design: .serif))
                        .textSelection(.enabled)
                }
            case .video:
                VStack(alignment: .leading, spacing: 16) {
                    if let videoURL = blessing.videoURL {
                        VideoBlessingPlayer(url: videoURL)
                    } else {
                        ContentUnavailableView("Video unavailable", systemImage: "video.slash")
                    }
                    Text(blessing.body ?? "")
                        .font(.system(.body, design: .serif))
                        .textSelection(.enabled)
                }
            }
        }
    }
}

private struct BlessingPhotoView: View {
    let url: URL

    var body: some View {
        Group {
            if url.isFileURL, let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image): image.resizable().scaledToFit()
                    case .failure:
                        ContentUnavailableView("Photo unavailable", systemImage: "photo.badge.exclamationmark")
                    case .empty:
                        ZStack {
                            AppTheme.canvas
                            ProgressView().accessibilityLabel("Loading photo")
                        }
                        .frame(height: 220)
                    @unknown default:
                        EmptyView()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: 520)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityLabel("Blessing photo")
    }
}

struct AudioBlessingPlayer: View {
    @State private var playback: MediaPlaybackController

    init(url: URL) {
        _playback = State(initialValue: MediaPlaybackController(url: url, kind: .voice))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let errorMessage = playback.errorMessage {
                Label(errorMessage, systemImage: "waveform.slash")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryInk)
                Button("Try again") { Task { await playback.retry() } }
                    .frame(minHeight: 44)
            } else {
                HStack(spacing: 12) {
                    Button {
                        Task { await playback.togglePlayback() }
                    } label: {
                        Group {
                            if playback.isPreparing {
                                ProgressView()
                            } else {
                                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                            }
                        }
                        .font(.headline)
                        .frame(width: 44, height: 44)
                        .foregroundStyle(.white)
                        .background(AppTheme.primary, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(playback.isPreparing)
                    .accessibilityLabel(playback.isPlaying ? "Pause recording" : "Play recording")

                    MediaPlayhead(playback: playback)
                }
            }
        }
        .task { await playback.prepare() }
        .onDisappear { playback.pause() }
    }
}

private struct MediaPlayhead: View {
    let playback: MediaPlaybackController

    var body: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { playback.currentTime },
                    set: { value in Task { await playback.seek(to: value) } }
                ),
                in: 0...max(playback.duration, 1)
            )
            .disabled(playback.duration <= 0)
            .accessibilityLabel("Recording position")
            .accessibilityValue(
                "\(MediaTimeFormatter.string(for: playback.currentTime)) of \(MediaTimeFormatter.string(for: playback.duration))"
            )

            HStack {
                Text(MediaTimeFormatter.string(for: playback.currentTime))
                Spacer()
                Text(MediaTimeFormatter.string(for: playback.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(AppTheme.secondaryInk)
            .accessibilityHidden(true)
        }
    }
}

struct VideoBlessingPlayer: View {
    @State private var playback: MediaPlaybackController
    @State private var isFullscreen = false

    init(url: URL) {
        _playback = State(initialValue: MediaPlaybackController(url: url, kind: .video))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let errorMessage = playback.errorMessage {
                ContentUnavailableView(
                    "Video unavailable",
                    systemImage: "video.slash",
                    description: Text(errorMessage)
                )
                Button("Try again") { Task { await playback.retry() } }
                    .frame(minHeight: 44)
            } else {
                ZStack(alignment: .topTrailing) {
                    VideoPlayer(player: playback.player)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .background(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Button {
                        isFullscreen = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.headline)
                            .frame(width: 44, height: 44)
                            .foregroundStyle(.white)
                            .background(.black.opacity(0.64), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .accessibilityLabel("Open video full screen")
                }
                MediaPlayhead(playback: playback)
            }
        }
        .task { await playback.prepare() }
        .onDisappear {
            if !isFullscreen { playback.pause() }
        }
        .fullScreenCover(isPresented: $isFullscreen) {
            FullscreenVideoPlayer(playback: playback)
        }
    }
}

private struct FullscreenVideoPlayer: View {
    @Environment(\.dismiss) private var dismiss
    let playback: MediaPlaybackController

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: playback.player)
                .ignoresSafeArea()
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .frame(width: 44, height: 44)
                            .foregroundStyle(.white)
                            .background(.black.opacity(0.64), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close full-screen video")
                }
                Spacer()
                MediaPlayhead(playback: playback)
                    .tint(.white)
                    .padding(16)
                    .background(.black.opacity(0.64), in: RoundedRectangle(cornerRadius: 16))
            }
            .padding()
        }
        .task { await playback.play() }
        .onDisappear { playback.pause() }
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
                ExpandablePassageText(
                    text: text,
                    title: reference.displayName,
                    translationName: model.selectedBibleTranslation.shortName
                )
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

struct ExpandablePassageText: View {
    let text: String
    let title: String
    let translationName: String
    @State private var isTruncated = false
    @State private var showingFullPassage = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TruncationAwareText(
                text: text,
                lineLimit: 5,
                font: .system(.body, design: .serif),
                isTruncated: $isTruncated
            )
            .textSelection(.enabled)

            if isTruncated {
                Button {
                    showingFullPassage = true
                } label: {
                    Label("Read full passage", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.iris)
            }
        }
        .sheet(isPresented: $showingFullPassage) {
            NavigationStack {
                ScrollView {
                    Text(text)
                        .font(.system(.title3, design: .serif))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AppTheme.pagePadding)
                }
                .background(AppTheme.canvas)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingFullPassage = false }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    Text(translationName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryInk)
                        .padding(.vertical, 8)
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

struct TruncationAwareText: View {
    let text: String
    let lineLimit: Int
    let font: Font
    @Binding var isTruncated: Bool
    @State private var limitedHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    var body: some View {
        Text(text)
            .font(font)
            .lineLimit(lineLimit)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: LimitedTextHeightKey.self, value: proxy.size.height)
                }
            }
            .overlay(alignment: .topLeading) {
                Text(text)
                    .font(font)
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .accessibilityHidden(true)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(key: FullTextHeightKey.self, value: proxy.size.height)
                        }
                    }
            }
            .onPreferenceChange(LimitedTextHeightKey.self) { limitedHeight = $0; updateTruncation() }
            .onPreferenceChange(FullTextHeightKey.self) { fullHeight = $0; updateTruncation() }
    }

    private func updateTruncation() {
        let truncated = fullHeight > limitedHeight + 1
        if isTruncated != truncated { isTruncated = truncated }
    }
}

private struct LimitedTextHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct FullTextHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct AvatarBadge: View {
    let member: Member
    let size: CGFloat

    var body: some View {
        Group {
            if let avatarURL = member.avatarURL {
                AsyncImage(url: avatarURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    initials
                }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .background(AppTheme.surface)
        .clipShape(Circle())
        .accessibilityLabel(member.displayName)
    }

    private var initials: some View {
        Text(member.initials)
            .font(.system(size: size * 0.31, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(avatarColor)
    }

    private var avatarColor: Color {
        [AppTheme.iris, AppTheme.dawn, AppTheme.candle][abs(member.tintSeed) % 3]
    }
}

struct CircleAvatarBadge: View {
    let circle: CircleGroup
    let size: CGFloat

    var body: some View {
        Group {
            if let photoURL = circle.photoURL {
                if photoURL.isFileURL, let image = UIImage(contentsOfFile: photoURL.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    AsyncImage(url: photoURL) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        .accessibilityLabel("\(circle.name) circle photo")
    }

    private var fallback: some View {
        Image(systemName: "person.3.fill")
            .font(.system(size: size * 0.36, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(AppTheme.primary.gradient)
    }
}
