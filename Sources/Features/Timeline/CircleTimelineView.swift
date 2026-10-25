import AVKit
import SwiftUI

private struct TimelineColumnWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = TimelineSizing.defaultWidth
}

private extension EnvironmentValues {
    var timelineColumnWidth: CGFloat {
        get { self[TimelineColumnWidthKey.self] }
        set { self[TimelineColumnWidthKey.self] = newValue }
    }
}

struct CircleTimelineView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var selection: BlessingSelection?
    @AppStorage("timeline.layoutMode") private var layout = TimelineLayoutMode.defaultMode
    @State private var selectedMemberID: UUID?
    @State private var showingPersonFilter = false
    @State private var presentedLanes: [TimelineLane] = []
    @State private var listIndex = TimelineListIndex(lanes: [])
    @AppStorage("timeline.columnWidth") private var storedWidth = TimelineSizing.defaultWidth

    var body: some View {
        ZStack {
            AppTheme.canvas.ignoresSafeArea()
            if !model.isShowingSavedTimeline && (model.isShowingCachedMetadata || (model.isPageLoading && model.lanes.isEmpty)) {
                CircleBlessingsPlaceholder()
                    .padding(AppTheme.pagePadding)
            } else if model.lanes.isEmpty {
                ContentUnavailableView(
                    "No days yet",
                    systemImage: "clock",
                    description: Text("Your circle’s blessings will gather here.")
                )
            } else if layout == .list {
                timelineList
            } else {
                TimelineThreadsView(lanes: presentedLanes, calendar: circleCalendar,
                    currentUserID: model.currentUser?.id, storedWidth: $storedWidth) { member, blessing in
                        selection = BlessingSelection(member: member, blessing: blessing)
                    }
                    .id(presentationScope)
            }
        }
        .navigationTitle("Timeline")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppTheme.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) { timelineControls }
        .refreshable { await model.refreshCurrentCircle() }
        .onChange(of: model.lanes, initial: true) { _, _ in rebuildPresentation() }
        .onChange(of: presentationScope) { _, _ in
            selectedMemberID = nil
            showingPersonFilter = false
            selection = nil
            rebuildPresentation()
        }
        .sheet(item: $selection) { selection in
            BlessingDetailView(
                member: selection.member,
                blessing: selection.blessing,
                allowsResponses: model.canRespond(to: selection.blessing)
            )
        }
    }

    private var timelineControls: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .trailing, spacing: 8) {
                    layoutMenu
                    if layout == .list, !model.lanes.isEmpty { personFilter }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                HStack(spacing: 12) {
                    if layout == .list, !model.lanes.isEmpty {
                        personFilter
                    } else {
                        Text("Timeline").font(.headline).foregroundStyle(AppTheme.ink)
                        Spacer(minLength: 0)
                    }
                    layoutMenu
                }
            }
        }
        .padding(.horizontal, AppTheme.pagePadding)
        .padding(.vertical, 8)
        .background(AppTheme.canvas)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timeline.controls")
    }

    private var layoutMenu: some View {
        Menu {
            Picker("Timeline layout", selection: $layout) {
                Text("List").tag(TimelineLayoutMode.list)
                Text("Threads").tag(TimelineLayoutMode.threads)
            }
            if layout == .threads {
                Section("Timeline size") {
                    Button("Smaller", systemImage: "minus.magnifyingglass") {
                        storedWidth = TimelineSizing.clamped(storedWidth - 24)
                    }.disabled(storedWidth <= 168)
                    Button("Larger", systemImage: "plus.magnifyingglass") {
                        storedWidth = TimelineSizing.clamped(storedWidth + 24)
                    }.disabled(storedWidth >= 360)
                    Button("Reset size") { storedWidth = TimelineSizing.defaultWidth }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: layout == .list ? "list.bullet" : "point.3.connected.trianglepath.dotted")
                    .accessibilityHidden(true)
                Text(layout.rawValue)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .font(.subheadline.weight(.semibold))
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .frame(minWidth: 112, minHeight: 32)
            .padding(.horizontal, 4)
            .background(AppTheme.surface, in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .frame(minWidth: 120, minHeight: 44)
        .buttonStyle(.plain)
        .controlSize(.large)
        .accessibilityLabel("Timeline layout")
        .accessibilityValue(layout.rawValue)
        .accessibilityIdentifier("timeline.layout")
    }

    private var presentationScope: String {
        "\(model.currentUser?.id.uuidString ?? "")|\(model.circle?.id.uuidString ?? "")|\(model.circle?.timeZoneIdentifier ?? "")"
    }

    private var circleCalendar: Calendar {
        CircleLocalDay.calendar(timeZoneIdentifier: model.circle?.timeZoneIdentifier ?? TimeZone.current.identifier)
    }

    private func rebuildPresentation() {
        presentedLanes = TimelinePresentation.lanes(model.lanes, calendar: circleCalendar)
        listIndex = TimelineListIndex(lanes: presentedLanes)
        selectedMemberID = listIndex.validSelection(selectedMemberID)
    }

    private var personFilter: some View {
        Button { showingPersonFilter = true } label: {
            HStack(spacing: 10) {
                if let member = listIndex.members.first(where: { $0.id == selectedMemberID }) {
                    AvatarBadge(member: member, size: 30)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "person.3").accessibilityHidden(true)
                }
                Text(selectedPersonName)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter by person")
        .accessibilityValue(selectedPersonName)
        .accessibilityIdentifier("timeline.personFilter")
        .popover(isPresented: $showingPersonFilter, arrowEdge: .top) {
            ScrollView {
                LazyVStack(spacing: 4) {
                    personChoice(nil)
                    ForEach(listIndex.members) { member in personChoice(member) }
                }
                .padding(8)
            }
            .frame(width: 300, height: verticalSizeClass == .compact ? 180 :
                (dynamicTypeSize.isAccessibilitySize ? 360 : min(360, CGFloat(listIndex.members.count + 1) * 52 + 16)))
            .background(AppTheme.surface)
            .presentationCompactAdaptation(.popover)
        }
    }

    private func personChoice(_ member: Member?) -> some View {
        Button {
            selectedMemberID = member?.id
            showingPersonFilter = false
        } label: {
            HStack(spacing: 12) {
                if let member {
                    AvatarBadge(member: member, size: 36)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "person.3")
                        .font(.system(size: 24))
                        .frame(width: 36, height: 36)
                        .accessibilityHidden(true)
                }
                Text(member?.displayName ?? "All")
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if selectedMemberID == member?.id {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(AppTheme.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(member?.displayName ?? "All")
        .accessibilityAddTraits(selectedMemberID == member?.id ? .isSelected : [])
    }

    private var selectedPersonName: String {
        listIndex.members.first { $0.id == selectedMemberID }?.displayName ?? "All"
    }

    private var timelineList: some View {
        let entries = listIndex.entries(for: selectedMemberID)
        return List {
            if entries.isEmpty {
                ContentUnavailableView("No blessings yet", systemImage: "clock",
                    description: Text(selectedMemberID == nil
                        ? "Visible blessings and joining events will appear here."
                        : "No events for this person in the loaded days. Load older days to see more history when available."))
                    .listRowBackground(AppTheme.canvas)
                    .listRowSeparator(.hidden)
            }
            ForEach(entries) { item in
                TimelineListRow(item: item, currentUserID: model.currentUser?.id, calendar: circleCalendar) { blessing in
                    selection = BlessingSelection(member: item.member, blessing: blessing)
                }
                .listRowBackground(AppTheme.canvas)
                .listRowSeparator(.hidden)
            }
            TimelineOlderDaysButton().listRowBackground(AppTheme.canvas)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("timeline.accessibleList")
        .foregroundStyle(AppTheme.ink)
    }
}

private struct TimelineListRow: View {
    let item: TimelineListEntry
    let currentUserID: UUID?
    let calendar: Calendar
    let onSelect: (Blessing) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(dateLabel)
                .font(.caption).foregroundStyle(AppTheme.secondaryInk)
            HStack {
                ProfileStreakAvatar(member: item.member, size: 36)
                Text(item.member.id == currentUserID ? "You" : item.member.displayName)
                    .font(.headline)
            }
            .accessibilityAddTraits(.isHeader)
            TimelineEventView(event: item.event, member: item.member, currentUserID: currentUserID, showsThread: false, onSelect: onSelect)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timeline.listRow.\(item.member.id.uuidString).\(item.id)")
    }

    private var dateLabel: String {
        var style = Date.FormatStyle.dateTime.month(.wide).day().year()
        style.timeZone = calendar.timeZone
        return item.sortDate.formatted(style)
    }
}

/// Geometry updates stay in Threads instead of invalidating the List/filter toolbar.
private struct TimelineThreadsView: View {
    let lanes: [TimelineLane]
    let calendar: Calendar
    let currentUserID: UUID?
    @Binding var storedWidth: Double
    let onSelect: (Member, Blessing) -> Void
    @State private var horizontalOffset: CGFloat = 0
    @State private var rows: [TimelineRow] = []
    @State private var rowsByID: [String: TimelineRow] = [:]
    @GestureState private var pinchScale = 1.0

    var body: some View {
        VStack(spacing: 0) {
            TimelineMemberHeader(lanes: lanes, currentUserID: currentUserID, horizontalOffset: horizontalOffset)
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in
                        TimelineDayRow(row: row, lanes: lanes, calendar: calendar,
                            currentUserID: currentUserID, onSelect: onSelect)
                    }
                    TimelineOlderDaysButton()
                }
                .padding(.leading, TimelineLayout.leadingPadding)
                .padding(.trailing, AppTheme.pagePadding)
                .padding(.top, 8)
                .padding(.bottom, 118)
            }
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x } action: { _, offset in
                horizontalOffset = offset
            }
            .overlayPreferenceValue(TimelineDateAnchors.self) { anchors in
                TimelineFrozenDates(rowsByID: rowsByID, anchors: anchors, calendar: calendar)
            }
            .scrollIndicators(.visible)
            .simultaneousGesture(MagnifyGesture()
                .updating($pinchScale) { value, scale, _ in scale = value.magnification }
                .onEnded { value in storedWidth = TimelineSizing.clamped(storedWidth * value.magnification) })
            .clipped()
        }
        .environment(\.timelineColumnWidth, TimelineSizing.clamped(storedWidth * pinchScale))
        .onChange(of: lanes, initial: true) { _, _ in
            rows = TimelineRow.rows(for: lanes, calendar: calendar)
            rowsByID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        }
    }
}

private struct TimelineOlderDaysButton: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if model.timelineNextBeforeDate != nil {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    Task { await model.loadMoreTimeline() }
                } label: {
                    HStack {
                        if model.isLoadingMoreTimeline { ProgressView() }
                        Text(model.isLoadingMoreTimeline ? "Loading older days…" : "Load older days")
                    }.frame(minHeight: 44)
                }.disabled(model.isLoadingMoreTimeline)
                .accessibilityIdentifier("timeline.loadOlder")
                if let error = model.timelineLoadError { Text(error).font(.footnote) }
            }
        }
    }
}

private enum TimelineLayout {
    static let dayColumnWidth: CGFloat = 62
    static let columnSpacing: CGFloat = 10
    static let leadingPadding: CGFloat = 6
}

private struct TimelineDateAnchors: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] { [:] }

    static func reduce(
        value: inout [String: Anchor<CGRect>],
        nextValue: () -> [String: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct TimelineFrozenDates: View {
    let rowsByID: [String: TimelineRow]
    let anchors: [String: Anchor<CGRect>]
    let calendar: Calendar

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                AppTheme.canvas
                    .frame(width: TimelineLayout.leadingPadding + TimelineLayout.dayColumnWidth)
                    .accessibilityHidden(true)
                ForEach(anchors.keys.sorted(), id: \.self) { id in
                    if let row = rowsByID[id], let anchor = anchors[id] {
                        let rect = geometry[anchor]
                        TimelineDateLabel(row: row, calendar: calendar)
                        .frame(height: rect.height, alignment: .topTrailing)
                        .offset(x: TimelineLayout.leadingPadding, y: rect.minY)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("timeline.dayColumn")
                    }
                }
                Rectangle()
                    .fill(AppTheme.divider)
                    .frame(width: 1)
                    .offset(x: TimelineLayout.leadingPadding + TimelineLayout.dayColumnWidth)
                    .accessibilityHidden(true)
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }

}

private struct TimelineDateLabel: View {
    let row: TimelineRow
    let calendar: Calendar

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(dayLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryInk)
            if row.kind == .joined {
                Text("Joined")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.primary)
            }
            ForEach(row.notificationTimes) { stamp in
                VStack(alignment: .trailing, spacing: 1) {
                    Image(systemName: stamp.kind == .daily ? "sun.max" : "moon")
                        .accessibilityHidden(true)
                    Text(timeLabel(stamp.date))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryInk)
                .accessibilityLabel("\(stamp.kind == .daily ? "Daily" : "Evening") notification, \(timeLabel(stamp.date))")
            }
        }
        .padding(.trailing, 8)
        .padding(.top, 3)
        .frame(width: TimelineLayout.dayColumnWidth, alignment: .trailing)
    }

    private var dayLabel: String {
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        style.timeZone = calendar.timeZone
        return row.day.formatted(style)
    }

    private func timeLabel(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime.hour().minute()
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }
}

private struct BlessingSelection: Identifiable {
    let member: Member
    let blessing: Blessing
    var id: UUID { blessing.id }
}

private struct TimelineMemberHeader: View {
    @Environment(\.timelineColumnWidth) private var columnWidth
    let lanes: [TimelineLane]
    let currentUserID: UUID?
    let horizontalOffset: CGFloat
    @ScaledMetric(relativeTo: .headline) private var nameLineHeight: CGFloat = 22

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: TimelineLayout.columnSpacing) {
                Color.clear
                    .frame(width: TimelineLayout.dayColumnWidth)
                    .accessibilityHidden(true)
                ForEach(lanes) { lane in
                    VStack(spacing: 4) {
                        ProfileStreakAvatar(member: lane.member, size: 40)
                        Text(lane.member.id == currentUserID ? "You" : lane.member.displayName)
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink)
                            .lineLimit(1)
                    }
                    .frame(width: columnWidth)
                }
            }
            .padding(.leading, TimelineLayout.leadingPadding)
            .padding(.trailing, AppTheme.pagePadding)
            .padding(.top, 2)
            .fixedSize(horizontal: true, vertical: false)
            .offset(x: -horizontalOffset)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .frame(height: 52 + nameLineHeight)
        .background(AppTheme.canvas)
        .clipped()
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timeline.memberHeader")
        .zIndex(10)
    }
}

private struct TimelineRow: Identifiable {
    enum Kind: Int {
        case prompt
        case joined
    }

    let day: Date
    let kind: Kind
    let eventsByMemberID: [UUID: [TimelineEvent]]
    let notificationTimes: [TimelineNotificationStamp]

    init(day: Date, kind: Kind, eventsByMemberID: [UUID: [TimelineEvent]]) {
        self.day = day
        self.kind = kind
        self.eventsByMemberID = eventsByMemberID
        notificationTimes = TimelinePresentation.notificationTimes(eventsByMemberID.values.flatMap { $0 })
    }

    var id: String { "\(day.timeIntervalSinceReferenceDate)-\(kind.rawValue)" }

    static func rows(for lanes: [TimelineLane], calendar: Calendar = .current) -> [TimelineRow] {
        var promptRows: [Date: [UUID: [TimelineEvent]]] = [:]
        var joinedRows: [Date: [UUID: TimelineEvent]] = [:]

        for lane in lanes {
            for event in lane.events {
                let day = calendar.startOfDay(for: event.date)
                if case .joinedCircle = event.status {
                    joinedRows[day, default: [:]][lane.member.id] = event
                } else {
                    promptRows[day, default: [:]][lane.member.id, default: []].append(event)
                }
            }
        }

        let prompts = promptRows.map {
            TimelineRow(day: $0.key, kind: .prompt, eventsByMemberID: $0.value.mapValues(sorted))
        }
        let joins = joinedRows.map {
            TimelineRow(
                day: $0.key,
                kind: .joined,
                eventsByMemberID: $0.value.mapValues { [$0] }
            )
        }
        return (prompts + joins).sorted { lhs, rhs in
            if lhs.day != rhs.day { return lhs.day > rhs.day }
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
    }
    private static func sorted(_ events: [TimelineEvent]) -> [TimelineEvent] {
        events.sorted { lhs, rhs in
            if lhs.promptKind != rhs.promptKind { return lhs.promptKind == .endOfDay }
            if lhs.isWelcome != rhs.isWelcome { return !lhs.isWelcome }
            return lhs.id < rhs.id
        }
    }
}

private struct TimelineDayRow: View {
    @Environment(\.timelineColumnWidth) private var columnWidth
    let row: TimelineRow
    let lanes: [TimelineLane]
    let calendar: Calendar
    let currentUserID: UUID?
    let onSelect: (Member, Blessing) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: TimelineLayout.columnSpacing) {
            TimelineDateLabel(row: row, calendar: calendar)
                .hidden()
                .frame(maxHeight: .infinity)
                .anchorPreference(key: TimelineDateAnchors.self, value: .bounds) { [row.id: $0] }
                .accessibilityHidden(true)

            ForEach(lanes) { lane in
                if let events = row.eventsByMemberID[lane.member.id] {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(events) { event in
                            TimelineEventView(
                                event: event,
                                member: lane.member,
                                currentUserID: currentUserID,
                                onSelect: { blessing in onSelect(lane.member, blessing) }
                            )
                        }
                    }
                    .frame(width: columnWidth)
                    .frame(maxHeight: .infinity, alignment: .top)
                } else {
                    TimelineConnectorView(
                        isVisible: row.day >= calendar.startOfDay(for: lane.member.joinedAt)
                    )
                    .frame(width: columnWidth)
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
    @Environment(AppModel.self) private var model
    let event: TimelineEvent
    let member: Member
    let currentUserID: UUID?
    var showsThread = true
    let onSelect: (Blessing) -> Void
    @State private var isBodyTruncated = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if showsThread {
                VStack(spacing: 0) {
                    marker
                        .frame(width: 24, height: 24)
                        .accessibilityHidden(true)
                    if !isJoinedMarker {
                        Rectangle()
                            .fill(AppTheme.divider)
                            .frame(width: 2)
                            .frame(maxHeight: .infinity)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                if event.isWelcome {
                    Label("Welcome blessing", systemImage: "hand.wave")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.iris)
                }
                if event.promptKind == .endOfDay {
                    Label("End of day", systemImage: "moon.stars.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.iris)
                }
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.bottom, isJoinedMarker ? 12 : 22)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: isBlessing ? .contain : .combine)
        .accessibilityValue(isBlessing ? "" : accessibilityContext)
    }

    private var isBlessing: Bool {
        if case .blessing = event.status { return true }
        return false
    }

    private var accessibilityContext: String {
        var style = Date.FormatStyle.dateTime.month(.wide).day().year()
        style.timeZone = TimeZone(identifier: model.circle?.timeZoneIdentifier ?? "") ?? .current
        return "\(member.displayName), \(event.date.formatted(style)), \(event.promptKind == .endOfDay ? "end-of-day" : "daily")"
    }

    private func accessibilityDescription(for blessing: Blessing) -> String {
        let mode = blessing.captureMode == .typed ? "text" : blessing.captureMode.rawValue
        return "\(accessibilityContext) \(mode) blessing. \(blessing.body ?? "")\(blessing.isLate ? ". Shared late" : "")\(blessing.scriptureReference.map { ". " + $0.displayName } ?? "")"
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
        case .waiting, .scheduled:
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
            SavedBlessingStatusView(blessing: blessing)
            Button { onSelect(blessing) } label: {
                VStack(alignment: .leading, spacing: 8) {
                    if let preview = model.resolvedBlessing(blessing).photoPreviewURL {
                        CachedPhotoPreview(url: preview)
                    }
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
                    .foregroundStyle(AppTheme.ink)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { submissionMetadata(blessing) }
                            .fixedSize(horizontal: true, vertical: false)
                        VStack(alignment: .leading, spacing: 4) { submissionMetadata(blessing) }
                    }
                    if let reference = blessing.scriptureReference {
                        Label(reference.displayName, systemImage: "book.closed")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.iris)
                    }
                }
                .padding(10)
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
            .accessibilityLabel(accessibilityDescription(for: blessing))
            .accessibilityInputLabels(["\(member.displayName) blessing", "Open blessing"])
            .accessibilityHint("Opens the complete blessing")
            TimelineResponderAvatars(blessing: blessing)
                .padding(.horizontal, 10)
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
        case .scheduled:
            EmptyView()
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

    @ViewBuilder
    private func submissionMetadata(_ blessing: Blessing) -> some View {
        Text(blessing.submittedAt, style: .time)
            .font(.caption2)
            .foregroundStyle(AppTheme.secondaryInk)
            .fixedSize()
        if blessing.isLate && !event.isWelcome {
            Label("Late", systemImage: "clock.badge.exclamationmark")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.candle)
                .labelStyle(.titleAndIcon)
                .fixedSize()
        } else if !event.isWelcome {
            Label("On time", systemImage: "flame.fill")
                .font(.caption2)
                .foregroundStyle(AppTheme.streakBlue)
                .labelStyle(.titleAndIcon)
                .fixedSize()
        }
    }
}

private struct TimelineResponderAvatars: View {
    @Environment(AppModel.self) private var model
    let blessing: Blessing
    @State private var summary: TimelineResponseSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let summary, summary.count > 0 {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        Text(responseCount(summary.count))
                        photos
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(responseCount(summary.count))
                        photos
                    }
                }
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryInk)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(responseAccessibilityLabel(summary))
                .accessibilityIdentifier("timeline.responses.\(blessing.id.uuidString)")
            }
        }
        .task(id: ResponseTaskID(blessingID: blessing.id, revision: model.timelineResponderRevision)) {
            let revision = model.timelineResponderRevision
            summary = nil
            let result = await model.timelineResponseSummary(for: blessing, revision: revision)
            guard !Task.isCancelled, model.timelineResponderRevision == revision else { return }
            summary = result
        }
    }

    private struct ResponseTaskID: Equatable {
        let blessingID: UUID
        let revision: UUID
    }

    private func responseCount(_ count: Int) -> String {
        count == 1 ? "1 response" : "\(count) responses"
    }

    @ViewBuilder private var photos: some View {
        if !responders.isEmpty {
            HStack(spacing: -6) {
                ForEach(responders.prefix(5)) { member in
                    AvatarBadge(member: member, size: 24)
                        .overlay { Circle().stroke(AppTheme.surface, lineWidth: 2) }
                }
                if responders.count > 5 {
                    Text("+\(responders.count - 5)")
                        .font(.caption2.weight(.semibold))
                        .padding(.leading, 10)
                }
            }
            .fixedSize()
        }
    }

    private var responders: [Member] {
        let members = Dictionary(uniqueKeysWithValues: (model.circle?.members ?? []).map { ($0.id, $0) })
        return (summary?.authorIDs ?? []).compactMap { members[$0] }
    }

    private func responseAccessibilityLabel(_ summary: TimelineResponseSummary) -> String {
        let names = responders.map(\.displayName)
        return responseCount(summary.count) + (names.isEmpty ? "" : ". From \(names.joined(separator: ", "))")
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
                        SavedBlessingButton(blessing: blessing)
                        if let reference = blessing.scriptureReference {
                            if model.isShowingSavedTimeline {
                                Label(reference.displayName, systemImage: "book.closed")
                            } else {
                                ScripturePassageView(reference: reference)
                            }
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
                    Text("\(BlessingTextPolicy.length(of: bodyText))/\(BlessingTextPolicy.maximumLength)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(BlessingTextPolicy.length(of: bodyText) > BlessingTextPolicy.maximumLength ? Color.red : AppTheme.secondaryInk)
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
        return (try? BlessingTextPolicy.validated(bodyText)) != nil
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
    @Environment(AppModel.self) private var model
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
        let blessing = model.resolvedBlessing(blessing)
        Group {
            switch blessing.captureMode {
            case .typed:
                VStack(alignment: .leading, spacing: 10) {
                    if let photoURL = blessing.photoURL {
                        BlessingPhotoView(url: photoURL, previewURL: blessing.photoPreviewURL)
                        SaveBlessingMediaButton(url: photoURL, kind: .photo)
                    }
                    Text(blessing.body ?? "")
                        .font(.system(.title3, design: .serif))
                        .textSelection(.enabled)
                }
            case .voice:
                VStack(alignment: .leading, spacing: 16) {
                    if let audioURL = blessing.audioURL {
                        AudioBlessingPlayer(url: audioURL)
                            .id(audioURL)
                    } else {
                        Label(MediaRetentionPolicy.isExpired(submittedAt: blessing.submittedAt)
                            ? "Audio expired after 30 days" : "Audio is unavailable", systemImage: "waveform.slash")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryInk)
                    }
                    if let photoURL = blessing.photoURL {
                        BlessingPhotoView(url: photoURL, previewURL: blessing.photoPreviewURL)
                        SaveBlessingMediaButton(url: photoURL, kind: .photo)
                    }
                    Text(blessing.body ?? "")
                        .font(.system(.body, design: .serif))
                        .textSelection(.enabled)
                }
            case .video:
                VStack(alignment: .leading, spacing: 16) {
                    if let videoURL = blessing.videoURL {
                        VideoBlessingPlayer(url: videoURL)
                            .id(videoURL)
                        SaveBlessingMediaButton(url: videoURL, kind: .video)
                    } else {
                        ContentUnavailableView(MediaRetentionPolicy.isExpired(submittedAt: blessing.submittedAt)
                            ? "Video expired after 30 days" : "Video unavailable", systemImage: "video.slash")
                    }
                    Text(blessing.body ?? "")
                        .font(.system(.body, design: .serif))
                        .textSelection(.enabled)
                }
            }
        }
    }
}

struct AudioBlessingPlayer: View {
    @Environment(AppModel.self) private var model
    @State private var playback: MediaPlaybackController
    private let url: URL

    init(url: URL) {
        self.url = url
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
                        .background(AppTheme.actionFill, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(playback.isPreparing)
                    .accessibilityLabel(playback.isPreparing ? "Loading recording" : playback.isPlaying ? "Pause recording" : "Play recording")

                    MediaPlayhead(playback: playback)
                }
            }
        }
        .onChange(of: url, initial: true) { _, value in playback.cacheAccountID = model.currentUser?.id; playback.updateURL(value) }
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
    @Environment(AppModel.self) private var model
    @State private var playback: MediaPlaybackController
    @State private var isFullscreen = false
    private let url: URL

    init(url: URL) {
        self.url = url
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
                    if playback.player.currentItem != nil {
                        VideoPlayer(player: playback.player)
                            .aspectRatio(playback.videoAspectRatio, contentMode: .fit)
                            .background(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else {
                        Color.black
                            .aspectRatio(playback.videoAspectRatio, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                Button {
                                    Task { await playback.play() }
                                } label: {
                                    Group {
                                        if playback.isPreparing { ProgressView().tint(.white) }
                                        else { Image(systemName: "play.fill").foregroundStyle(.white) }
                                    }
                                    .frame(width: 44, height: 44)
                                }
                                .accessibilityLabel("Play video")
                                .disabled(playback.isPreparing)
                            }
                    }

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
                    .disabled(playback.isPreparing)
                }
            }
        }
        .onChange(of: url, initial: true) { _, value in playback.cacheAccountID = model.currentUser?.id; playback.updateURL(value) }
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
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(key: FullTextHeightKey.self, value: proxy.size.height)
                        }
                    }
                    .accessibilityHidden(true)
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
            IdentityPhotoImage(key: .member(member.id), url: member.avatarURL) { initials }
        }
        .frame(width: size, height: size)
        .background(AppTheme.surface)
        .clipShape(Circle())
        .accessibilityLabel(member.displayName)
    }

    private var initials: some View {
        Text(member.initials)
            .font(.system(size: size * 0.31, weight: .bold, design: .rounded))
            .foregroundStyle(AppTheme.surface)
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
            IdentityPhotoImage(key: .circle(circle.id), url: circle.photoURL) { fallback }
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
            .background(AppTheme.actionFill.gradient)
    }
}


