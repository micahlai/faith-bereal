import PhotosUI
import SwiftUI

private struct CircleHeaderIdentity: View {
    let circle: CircleGroup
    let size: CGFloat

    var body: some View {
        Group {
            if let photoURL = circle.photoURL {
                if photoURL.isFileURL, let image = UIImage(contentsOfFile: photoURL.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    AsyncImage(url: photoURL) { image in
                        image.resizable().scaledToFill()
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
        .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        Image(systemName: "circle.hexagongrid.fill")
            .font(.system(size: size * 0.65, weight: .light))
            .foregroundStyle(AppTheme.primary)
            .frame(width: size, height: size)
    }
}

struct CircleView: View {
    @Environment(AppModel.self) private var model
    @State private var joinCode = ""
    @State private var showingJoin = false
    @State private var showingCreate = false
    @State private var showingSettings = false

    var body: some View {
        ZStack {
            AppTheme.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if model.circle == nil {
                        emptyHeader
                    } else {
                        circleHeader
                        members
                    }
                    actions
                }
                .frame(maxWidth: 680)
                .padding(AppTheme.pagePadding)
                .padding(.bottom, 100)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(model.circle == nil ? "Let’s get started" : "Circle")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingJoin) { joinSheet }
        .fullScreenCover(isPresented: $showingCreate) { createSheet }
        .onAppear { presentPendingInviteIfNeeded() }
        .onChange(of: model.pendingInviteCode) { _, _ in presentPendingInviteIfNeeded() }
        .onChange(of: showingJoin) { wasShowing, isShowing in
            if wasShowing && !isShowing { model.clearPendingInvite() }
        }
    }

    private var emptyHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "person.3.sequence.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(AppTheme.primary)
            Text("Blessings are better together")
                .font(.system(.title, design: .serif, weight: .semibold))
            Text("Join with a code from someone you know, or start a new circle and invite them.")
                .foregroundStyle(AppTheme.secondaryInk)
        }
        .blessingCard()
    }

    private var circleHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                if let circle = model.circle {
                    CircleHeaderIdentity(circle: circle, size: 68)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.circle?.name ?? "Your circle")
                        .font(.system(.title2, design: .serif, weight: .semibold))
                    Text("\(model.circle?.members.count ?? 0) members")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryInk)
                }
            }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Invite code")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryInk)
                    Text(model.circle?.inviteCode ?? "—")
                        .font(.system(.title3, design: .monospaced, weight: .bold))
                        .textSelection(.enabled)
                }
                Spacer()
                ShareLink(item: inviteURL(for: model.circle?.inviteCode ?? "")) {
                    Label("Share join link", systemImage: "square.and.arrow.up")
                        .frame(minHeight: 44)
                }
                .disabled(model.circle?.inviteCode.isEmpty != false)
            }

            Divider()
            Button { showingSettings = true } label: {
                HStack {
                    Label("Circle settings", systemImage: "slider.horizontal.3")
                    Spacer()
                    Text(windowSummary)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryInk)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("circle-settings-button")
            .sheet(isPresented: $showingSettings) {
                if let circle = model.circle {
                    CircleSettingsView(circle: circle, isPresented: $showingSettings)
                }
            }
        }
        .blessingCard()
    }

    private var members: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("People")
                .font(.headline)
            ForEach(model.circle?.members ?? []) { member in
                HStack(spacing: 12) {
                    AvatarBadge(member: member, size: 42)
                    Text(member.id == model.currentUser?.id ? "\(member.displayName) (you)" : member.displayName)
                        .foregroundStyle(AppTheme.ink)
                    Spacer()
                    if member.id == model.circle?.ownerID {
                        Text("Owner")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryInk)
                    }
                }
                .frame(minHeight: 44)
            }
        }
        .blessingCard()
    }

    private var windowSummary: String {
        guard let circle = model.circle else { return "" }
        let duration = circle.responseWindowMinutes == 1
            ? "1 min"
            : "\(circle.responseWindowMinutes) min"
        return circle.allowsLateBlessings ? "\(duration) · Late allowed" : duration
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button { showingJoin = true } label: {
                Label(model.circle == nil ? "Join a circle" : "Join another circle", systemImage: "person.badge.plus")
                    .frame(maxWidth: .infinity, minHeight: AppTheme.controlHeight)
            }
            .buttonStyle(MannaPrimaryButtonStyle())
            .tint(AppTheme.actionFill)
            Button { showingCreate = true } label: {
                Label("Create a circle", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity, minHeight: AppTheme.controlHeight)
            }
            .buttonStyle(.bordered)
            if model.usesAuthentication {
                Button("Sign out", role: .destructive) {
                    Task { await model.signOut() }
                }
                .frame(maxWidth: .infinity, minHeight: AppTheme.controlHeight)
                .buttonStyle(.bordered)
            }
        }
    }

    private var joinSheet: some View {
        NavigationStack {
            Form {
                Section("Circle code") {
                    TextField("LIGHT7", text: $joinCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .accessibilityHint("Enter the six character code shared by a circle member")
                }
                Section {
                    Button("Join circle") {
                        Task {
                            if await model.joinCircle(code: joinCode) { showingJoin = false }
                        }
                    }
                    .disabled(joinCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Join a circle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingJoin = false } }
            }
        }
        .presentationDetents([.medium])
    }

    private var createSheet: some View {
        CircleCreationView(isPresented: $showingCreate)
    }

    private func presentPendingInviteIfNeeded() {
        guard let code = model.pendingInviteCode else { return }
        joinCode = code
        showingJoin = true
    }

    private func inviteURL(for code: String) -> URL {
        CircleInviteLink.webURL(for: code) ?? CircleInviteLink.websiteURL
    }
}

private struct CircleCreationView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var timeZoneIdentifier: String
    @State private var randomWindowStart: Date
    @State private var randomWindowEnd: Date
    @State private var endOfDayTime: Date
    @State private var selectedIndex: Double
    @State private var allowsLateBlessings = false
    @State private var repeatWindowMinutes = 120
    @State private var isCreating = false
    @State private var selectedCirclePhoto: PhotosPickerItem?
    @State private var pendingCirclePhotoResize: PendingPhotoResize?
    @State private var circlePhotoURL: URL?
    @State private var isPreparingCirclePhoto = false
    @State private var step = 0

    private let stepTitles = [
        "Circle name", "Circle photo", "Time zone", "Random blessing time", "Response window", "Late blessings",
        "End-of-day blessing", "Repeat blessings", "Review your circle",
    ]

    init(isPresented: Binding<Bool>) {
        _isPresented = isPresented
        let defaults = CircleConfiguration.defaults()
        _timeZoneIdentifier = State(initialValue: defaults.timeZoneIdentifier)
        _randomWindowStart = State(initialValue: Self.wallClockDate(minutes: defaults.randomWindowStartMinutes))
        _randomWindowEnd = State(initialValue: Self.wallClockDate(minutes: defaults.randomWindowEndMinutes))
        _endOfDayTime = State(initialValue: Self.wallClockDate(minutes: defaults.endOfDayMinutes))
        _selectedIndex = State(
            initialValue: Double(ResponseWindowOptions.minutes.firstIndex(of: defaults.responseWindowMinutes) ?? 4)
        )
        _allowsLateBlessings = State(initialValue: defaults.allowsLateBlessings)
        _repeatWindowMinutes = State(initialValue: defaults.repeatWindowMinutes)
    }

    private var selectedMinutes: Int {
        let index = min(max(Int(selectedIndex.rounded()), 0), ResponseWindowOptions.minutes.count - 1)
        return ResponseWindowOptions.minutes[index]
    }

    private var randomWindowStartMinutes: Int { Self.minutes(from: randomWindowStart) }
    private var randomWindowEndMinutes: Int { Self.minutes(from: randomWindowEnd) }
    private var endOfDayMinutes: Int { Self.minutes(from: endOfDayTime) }

    private var configuration: CircleConfiguration {
        CircleConfiguration(
            name: name,
            timeZoneIdentifier: timeZoneIdentifier,
            randomWindowStartMinutes: randomWindowStartMinutes,
            randomWindowEndMinutes: randomWindowEndMinutes,
            responseWindowMinutes: selectedMinutes,
            allowsLateBlessings: allowsLateBlessings,
            repeatWindowMinutes: repeatWindowMinutes,
            endOfDayMinutes: endOfDayMinutes
        )
    }

    var body: some View {
        let circlePhotoButtonTitle =
            circlePhotoURL == nil
            ? "Choose circle photo"
            : "Change circle photo"
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Text("Step \(step + 1) of \(stepTitles.count)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.secondaryInk)
                    ProgressView(value: Double(step + 1), total: Double(stepTitles.count))
                        .tint(AppTheme.primary)
                        .accessibilityLabel("Circle setup progress")
                    Text(stepTitles[step])
                        .font(.system(.title, design: .serif, weight: .regular))
                        .accessibilityAddTraits(.isHeader)
                }
                .padding(AppTheme.pagePadding)
                Form {
                    if step == 1 {
                        Section {
                            HStack(spacing: 16) {
                                creationPhotoPreview
                                VStack(alignment: .leading, spacing: 6) {
                                    PhotosPicker(selection: $selectedCirclePhoto, matching: .images) {
                                        Label(
                                            circlePhotoButtonTitle,
                                            systemImage: "photo"
                                        )
                                        .frame(minHeight: 44)
                                    }
                                    if circlePhotoURL != nil {
                                        Button("Remove photo", role: .destructive) {
                                            circlePhotoURL = nil
                                            selectedCirclePhoto = nil
                                        }
                                        .frame(minHeight: 44)
                                    }
                                }
                            }
                            if isPreparingCirclePhoto {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("Preparing photo…")
                                        .foregroundStyle(AppTheme.secondaryInk)
                                }
                            }
                        } header: {
                            Text("Circle photo")
                        } footer: {
                            Text("Optional. You can change this later in Circle settings.")
                        }
                    }

                    if step == 0 {
                        Section {
                            TextField("Circle name", text: $name)
                                .textContentType(.organizationName)
                                .accessibilityIdentifier("create-circle-name")
                        } footer: {
                            Text(
                                "Choose a name your friends will recognize. It appears in the circle menu, invitations, and notifications."
                            )
                        }
                    }
                    if step == 2 {
                        Section {
                            NavigationLink {
                                CircleTimeZonePicker(selection: $timeZoneIdentifier)
                            } label: {
                                LabeledContent("Time zone", value: timeZoneDisplayName)
                            }
                        } header: {
                            Text("Circle")
                        } footer: {
                            Text("The selected time zone keeps one shared blessing day for members wherever they live.")
                        }
                    }

                    if step == 3 {
                        Section {
                            DatePicker(
                                "Earliest time",
                                selection: $randomWindowStart,
                                displayedComponents: .hourAndMinute
                            )
                            DatePicker(
                                "Latest time",
                                selection: $randomWindowEnd,
                                displayedComponents: .hourAndMinute
                            )
                            if randomWindowEndMinutes <= randomWindowStartMinutes {
                                Label(
                                    "Latest time must be after earliest time.", systemImage: "exclamationmark.triangle"
                                )
                                .font(.caption)
                                .foregroundStyle(.red)
                            }
                        } header: {
                            Text("Random blessing time")
                        } footer: {
                            Text(
                                "Everyone receives the same random invitation within this range, in \(timeZoneDisplayName). The default is noon to 10 p.m."
                            )
                        }
                    }

                    if step == 4 {
                        Section {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text("Response window")
                                        .font(.headline)
                                    Spacer()
                                    Text(selectedMinutes == 1 ? "1 minute" : "\(selectedMinutes) minutes")
                                        .font(.headline.monospacedDigit())
                                        .foregroundStyle(AppTheme.primary)
                                }
                                Slider(
                                    value: $selectedIndex,
                                    in: 0...Double(ResponseWindowOptions.minutes.count - 1),
                                    step: 1
                                ) {
                                    Text("Response window length")
                                } minimumValueLabel: {
                                    Text("1m").font(.caption2)
                                } maximumValueLabel: {
                                    Text("3h").font(.caption2)
                                }
                                .tint(AppTheme.primary)
                                .accessibilityValue(selectedMinutes == 1 ? "1 minute" : "\(selectedMinutes) minutes")
                            }
                            .padding(.vertical, 6)
                        } footer: {
                            Text(
                                "This is how long members have to open the blessing composer after the notification. Once inside, they can finish and send after the timer ends."
                            )
                        }
                    }

                    if step == 5 {
                        Section {
                            Toggle("Allow late blessings", isOn: $allowsLateBlessings)
                        } footer: {
                            Text(
                                "Late posts remain available until the next daily prompt and are labeled in the timeline."
                            )
                        }
                    }

                    if step == 6 {
                        Section {
                            DatePicker(
                                "End-of-day time",
                                selection: $endOfDayTime,
                                displayedComponents: .hourAndMinute
                            )
                            if endOfDayMinutes < randomWindowEndMinutes {
                                Label(
                                    "End of day cannot be before the latest random blessing time.",
                                    systemImage: "exclamationmark.triangle"
                                )
                                .font(.caption)
                                .foregroundStyle(.red)
                            }
                        } header: {
                            Text("End-of-day blessing")
                        } footer: {
                            Text(
                                "A second, untimed reflection opens at this time and remains available for up to five hours."
                            )
                        }
                    }

                    if step == 7 {
                        Section {
                            Picker("Reuse window", selection: $repeatWindowMinutes) {
                                ForEach(RepeatWindowOptions.minutes, id: \.self) { minutes in
                                    Text(Self.durationLabel(minutes)).tag(minutes)
                                }
                            }
                        } header: {
                            Text("Repeat blessings")
                        } footer: {
                            Text(
                                "Members can reuse their own blessing from another circle within this much time of sending it."
                            )
                        }
                    }

                    if step == 8 {
                        Section {
                            LabeledContent("Name", value: name)
                            HStack {
                                creationPhotoPreview;
                                Text(circlePhotoURL == nil ? "Default circle image" : "Custom circle photo")
                            }
                            LabeledContent("Time zone", value: timeZoneDisplayName)
                            LabeledContent(
                                "Random blessing time",
                                value:
                                    "\(randomWindowStart.formatted(date: .omitted, time: .shortened)) – \(randomWindowEnd.formatted(date: .omitted, time: .shortened))"
                            )
                            LabeledContent("Response window", value: Self.durationLabel(selectedMinutes))
                            LabeledContent("Late blessings", value: allowsLateBlessings ? "Allowed" : "Not allowed")
                            LabeledContent(
                                "End-of-day time", value: endOfDayTime.formatted(date: .omitted, time: .shortened))
                            LabeledContent("Reuse window", value: Self.durationLabel(repeatWindowMinutes))
                        } footer: {
                            Text(
                                "Nothing has been created yet. These settings apply from today. Use Back to adjust them, or create your circle to get its join code."
                            )
                        }
                    }
                }
                .id(step)
                .scrollContentBackground(.hidden)
            }
            .background(AppTheme.canvas)
            .safeAreaInset(edge: .bottom) {
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .trailing, spacing: 8))
                    : AnyLayout(HStackLayout(spacing: 12))
                layout {
                    if step > 0 {
                        Button {
                            step -= 1
                        } label: {
                            Text("Back").fixedSize().frame(minWidth: 64, minHeight: AppTheme.controlHeight)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isCreating)
                        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil, alignment: .leading)
                    }
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 12) }
                    Button {
                        if step == stepTitles.count - 1 {
                            isCreating = true
                            Task { await createCircle() }
                        } else {
                            step += 1
                        }
                    } label: {
                        HStack {
                            if isCreating { ProgressView() }
                            Text(step == stepTitles.count - 1 ? "Create circle" : "Continue")
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(minWidth: 104, minHeight: AppTheme.controlHeight)
                    }
                    .buttonStyle(MannaPrimaryButtonStyle())
                    .tint(AppTheme.actionFill)
                    .disabled(isCreating || isPreparingCirclePhoto || !canContinue)
                    .accessibilityIdentifier(
                        step == stepTitles.count - 1 ? "create-circle-submit" : "create-circle-continue")
                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.vertical, 12)
                .background(.bar)
            }
            .navigationTitle("New circle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                        .disabled(isCreating)
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(isCreating)
        .task(id: selectedCirclePhoto) {
            guard let selectedCirclePhoto else { return }
            isPreparingCirclePhoto = true
            defer { isPreparingCirclePhoto = false }
            do {
                guard let data = try await selectedCirclePhoto.loadTransferable(type: Data.self) else { return }
                pendingCirclePhotoResize = try PendingPhotoResize(data: data)
            } catch {
                model.message = "Couldn’t prepare that circle photo: \(error.localizedDescription)"
            }
        }
        .sheet(item: $pendingCirclePhotoResize, onDismiss: { selectedCirclePhoto = nil }) { photo in
            PhotoResizeEditor(
                title: "Resize circle photo",
                photo: photo,
                onCancel: { pendingCirclePhotoResize = nil },
                onUsePhoto: { url in
                    circlePhotoURL = url
                    pendingCirclePhotoResize = nil
                }
            )
        }
    }

    private var canContinue: Bool {
        switch step {
        case 0: (1...80).contains(name.trimmingCharacters(in: .whitespacesAndNewlines).count)
        case 3: randomWindowEndMinutes > randomWindowStartMinutes
        case 6: endOfDayMinutes >= randomWindowEndMinutes
        case 8: configuration.isValid
        default: true
        }
    }

    @ViewBuilder private var creationPhotoPreview: some View {
        if let circlePhotoURL,
            circlePhotoURL.isFileURL,
            let image = UIImage(contentsOfFile: circlePhotoURL.path)
        {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 72)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityHidden(true)
        } else {
            Image(systemName: "circle.hexagongrid.fill")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(AppTheme.primary)
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
        }
    }

    private func createCircle() async {
        let selectedConfiguration = configuration
        guard await model.createCircle(configuration: selectedConfiguration) else {
            isCreating = false
            return
        }
        if let circlePhotoURL {
            _ = await model.updateCirclePhoto(circlePhotoURL)
        }
        isCreating = false
        isPresented = false
    }

    private var timeZoneDisplayName: String {
        guard let zone = TimeZone(identifier: timeZoneIdentifier) else { return timeZoneIdentifier }
        return zone.localizedName(for: .standard, locale: .current) ?? timeZoneIdentifier
    }

    private static func wallClockDate(minutes: Int) -> Date {
        Calendar.current.date(
            from: DateComponents(year: 2001, month: 1, day: 1, hour: minutes / 60, minute: minutes % 60)
        ) ?? .now
    }

    private static func minutes(from date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private static func durationLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        if minutes % 60 == 0 {
            let hours = minutes / 60
            return hours == 1 ? "1 hour" : "\(hours) hours"
        }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}

private struct CircleSettingsView: View {
    @Environment(AppModel.self) private var model
    let circle: CircleGroup
    @Binding var isPresented: Bool
    @State private var selectedIndex: Double
    @State private var allowsLateBlessings: Bool
    @State private var repeatWindowMinutes: Int
    @State private var name: String
    @State private var timeZoneIdentifier: String
    @State private var randomWindowStart: Date
    @State private var randomWindowEnd: Date
    @State private var endOfDayTime: Date
    @State private var isSaving = false
    @State private var isLeaving = false
    @State private var showingLeaveConfirmation = false
    @State private var showingForcePromptConfirmation = false
    @State private var showingCodeRegenerationConfirmation = false
    @State private var showingOwnershipTransfer = false
    @State private var showingDiscardChangesConfirmation = false
    @State private var memberToRemove: Member?
    @State private var isRemovingMember = false
    @State private var isRegeneratingCode = false
    @State private var selectedCirclePhoto: PhotosPickerItem?
    @State private var pendingCirclePhotoResize: PendingPhotoResize?
    @State private var pendingCirclePhotoURL: URL?
    @State private var circlePhotoChanged = false
    @State private var isPreparingCirclePhoto = false

    init(circle: CircleGroup, isPresented: Binding<Bool>) {
        self.circle = circle
        _isPresented = isPresented
        let index = ResponseWindowOptions.minutes.firstIndex(of: circle.responseWindowMinutes) ?? 4
        _selectedIndex = State(initialValue: Double(index))
        _allowsLateBlessings = State(initialValue: circle.allowsLateBlessings)
        _repeatWindowMinutes = State(initialValue: circle.repeatWindowMinutes)
        _name = State(initialValue: circle.name)
        _timeZoneIdentifier = State(initialValue: circle.timeZoneIdentifier)
        _randomWindowStart = State(initialValue: Self.wallClockDate(minutes: circle.randomWindowStartMinutes))
        _randomWindowEnd = State(initialValue: Self.wallClockDate(minutes: circle.randomWindowEndMinutes))
        _endOfDayTime = State(initialValue: Self.wallClockDate(minutes: circle.endOfDayMinutes))
        _pendingCirclePhotoURL = State(initialValue: circle.photoURL)
    }

    private var selectedMinutes: Int {
        let index = min(max(Int(selectedIndex.rounded()), 0), ResponseWindowOptions.minutes.count - 1)
        return ResponseWindowOptions.minutes[index]
    }

    private var randomWindowStartMinutes: Int { Self.minutes(from: randomWindowStart) }
    private var randomWindowEndMinutes: Int { Self.minutes(from: randomWindowEnd) }
    private var endOfDayMinutes: Int { Self.minutes(from: endOfDayTime) }
    private var settingsAreValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && randomWindowEndMinutes > randomWindowStartMinutes
            && endOfDayMinutes >= randomWindowEndMinutes
    }
    private var isOwner: Bool { model.circle?.ownerID == model.currentUser?.id }
    private var hasUnsavedChanges: Bool {
        guard isOwner else { return false }
        return name != circle.name
            || timeZoneIdentifier != circle.timeZoneIdentifier
            || randomWindowStartMinutes != circle.randomWindowStartMinutes
            || randomWindowEndMinutes != circle.randomWindowEndMinutes
            || selectedMinutes != circle.responseWindowMinutes
            || allowsLateBlessings != circle.allowsLateBlessings
            || repeatWindowMinutes != circle.repeatWindowMinutes
            || endOfDayMinutes != circle.endOfDayMinutes
            || circlePhotoChanged
    }

    var body: some View {
        NavigationStack {
            Form {
                if isOwner {
                    Section {
                        HStack(spacing: 16) {
                            CircleAvatarBadge(circle: photoPreviewCircle, size: 72)
                            VStack(alignment: .leading, spacing: 6) {
                                PhotosPicker(selection: $selectedCirclePhoto, matching: .images) {
                                    Label("Choose circle photo", systemImage: "photo")
                                        .frame(minHeight: 44)
                                }
                                if pendingCirclePhotoURL != nil {
                                    Button("Remove photo", role: .destructive) {
                                        pendingCirclePhotoURL = nil
                                        selectedCirclePhoto = nil
                                        circlePhotoChanged = true
                                    }
                                    .frame(minHeight: 44)
                                }
                            }
                        }

                        if isPreparingCirclePhoto {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Preparing photo…")
                                    .foregroundStyle(AppTheme.secondaryInk)
                            }
                        }

                    } header: {
                        Text("Circle photo")
                    } footer: {
                        Text("Shown on the Circle page and in notifications for this circle.")
                    }

                    Section("Circle") {
                        TextField("Circle name", text: $name)
                            .textContentType(.organizationName)
                        NavigationLink {
                            CircleTimeZonePicker(selection: $timeZoneIdentifier)
                        } label: {
                            LabeledContent("Time zone", value: timeZoneDisplayName)
                        }
                    }

                    Section {
                        LabeledContent("Current code") {
                            Text(currentInviteCode.isEmpty ? "Unavailable" : currentInviteCode)
                                .font(.body.monospaced().weight(.semibold))
                                .textSelection(.enabled)
                                .accessibilityIdentifier("circle-settings-invite-code")
                        }
                        ShareLink(item: inviteURL) {
                            Label("Share join link", systemImage: "square.and.arrow.up")
                                .frame(minHeight: 44)
                        }
                        .disabled(currentInviteCode.isEmpty || isRegeneratingCode)
                        Button(role: .destructive) {
                            showingCodeRegenerationConfirmation = true
                        } label: {
                            HStack {
                                Label("Regenerate invite code", systemImage: "arrow.triangle.2.circlepath")
                                Spacer()
                                if isRegeneratingCode { ProgressView() }
                            }
                            .frame(minHeight: 44)
                        }
                        .disabled(isRegeneratingCode)
                        .accessibilityIdentifier("regenerate-invite-code")
                    } header: {
                        Text("Invitations")
                    } footer: {
                        Text("Regenerating immediately invalidates the previous code. Existing members stay in the circle.")
                    }

                    Section {
                        Button {
                            showingForcePromptConfirmation = true
                        } label: {
                            HStack {
                                Label("Force blessing notification", systemImage: "bell.badge.fill")
                                Spacer()
                                if model.isForcingCirclePrompt { ProgressView() }
                            }
                            .frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("force-blessing-notification")
                        .disabled(isSaving || model.isForcingCirclePrompt)
                    } header: {
                        Text("Owner testing")
                    } footer: {
                        if model.usesAuthentication {
                            Text("Immediately opens today’s response window and sends a real notification and Live Activity request to every registered member device. Use sparingly.")
                        } else {
                            Text("Immediately restarts today’s local demo window and Live Activity. No remote notifications are sent in local mode.")
                        }
                    }

                    Section {
                        DatePicker(
                            "Earliest time",
                            selection: $randomWindowStart,
                            displayedComponents: .hourAndMinute
                        )
                        DatePicker(
                            "Latest time",
                            selection: $randomWindowEnd,
                            displayedComponents: .hourAndMinute
                        )
                        if randomWindowEndMinutes <= randomWindowStartMinutes {
                            Label("Latest time must be after earliest time.", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    } header: {
                        Text("Random blessing time")
                    } footer: {
                        Text("The server chooses one shared moment inside this range using \(timeZoneIdentifier).")
                    }

                    Section {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("Response window")
                                    .font(.headline)
                                Spacer()
                                Text(selectedMinutes == 1 ? "1 minute" : "\(selectedMinutes) minutes")
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(AppTheme.primary)
                            }

                            Slider(
                                value: $selectedIndex,
                                in: 0...Double(ResponseWindowOptions.minutes.count - 1),
                                step: 1
                            ) {
                                Text("Response window length")
                            } minimumValueLabel: {
                                Text("1m").font(.caption2)
                            } maximumValueLabel: {
                                Text("3h").font(.caption2)
                            }
                            .tint(AppTheme.primary)
                            .accessibilityValue(selectedMinutes == 1 ? "1 minute" : "\(selectedMinutes) minutes")
                        }
                        .padding(.vertical, 6)
                    } footer: {
                        Text("This length is used when future daily prompts are scheduled. Today’s deadline does not move.")
                    }

                    Section {
                        Toggle("Allow late blessings", isOn: $allowsLateBlessings)
                    } footer: {
                        Text("Members may share after the response window until the next daily prompt. Their post is marked Late in the timeline.")
                    }

                    Section {
                        DatePicker(
                            "End-of-day time",
                            selection: $endOfDayTime,
                            displayedComponents: .hourAndMinute
                        )
                        if endOfDayMinutes < randomWindowEndMinutes {
                            Label("End of day cannot be before the latest random blessing time.", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    } header: {
                        Text("End-of-day blessing")
                    } footer: {
                        Text("This opens a second reflection with no countdown. It closes after five hours or when the next daily blessing begins.")
                    }

                    Section {
                        Picker("Reuse window", selection: $repeatWindowMinutes) {
                            ForEach(RepeatWindowOptions.minutes, id: \.self) { minutes in
                                Text(Self.durationLabel(minutes)).tag(minutes)
                            }
                        }
                    } header: {
                        Text("Repeat blessings")
                    } footer: {
                        Text("A member can reuse their own blessing from another circle only within this much time of when they originally sent it.")
                    }

                    if circle.members.count > 1 {
                        Section {
                            Button {
                                showingOwnershipTransfer = true
                            } label: {
                                Label("Transfer circle ownership", systemImage: "person.2.arrow.trianglehead.counterclockwise")
                            }
                        } header: {
                            Text("Ownership")
                        } footer: {
                            Text("The new owner can change circle settings and transfer ownership again. You will remain a member.")
                        }

                        Section("Manage members") {
                            ForEach((model.circle?.members ?? circle.members).filter { $0.id != model.currentUser?.id }) { member in
                                HStack(spacing: 12) {
                                    AvatarBadge(member: member, size: 36)
                                    Text(member.displayName)
                                    Spacer()
                                    Button("Remove", role: .destructive) {
                                        memberToRemove = member
                                    }
                                    .disabled(isRemovingMember)
                                }
                                .frame(minHeight: 44)
                            }
                        }
                    }

                } else {
                    Section("Circle") {
                        LabeledContent("Name", value: circle.name)
                        LabeledContent("Time zone", value: timeZoneDisplayName)
                    }
                    Section("Schedule") {
                        LabeledContent("Response window", value: selectedMinutes == 1 ? "1 minute" : "\(selectedMinutes) minutes")
                        LabeledContent("Late blessings", value: allowsLateBlessings ? "Allowed" : "Not allowed")
                        LabeledContent("Reuse window", value: Self.durationLabel(repeatWindowMinutes))
                        LabeledContent("End-of-day blessing", value: endOfDayTime.formatted(date: .omitted, time: .shortened))
                    }
                }

                Section {
                    Button("Leave circle", role: .destructive) {
                        showingLeaveConfirmation = true
                    }
                    .disabled(isLeaving)
                } footer: {
                    if isOwner {
                        Text(circle.members.count == 1
                             ? "Because you are the only member, leaving will delete this circle."
                             : "Ownership will pass to the longest-standing remaining member.")
                    } else {
                        Text("Your blessing history remains in the circle, but you will no longer be able to view it.")
                    }
                }
            }
            .navigationTitle("Circle settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasUnsavedChanges {
                            showingDiscardChangesConfirmation = true
                        } else {
                            isPresented = false
                        }
                    }
                    .disabled(isSaving)
                }
                if isOwner {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(isSaving ? "Saving…" : "Save") {
                            Task { await saveChanges() }
                        }
                        .disabled(
                            isSaving
                                || isPreparingCirclePhoto
                                || !settingsAreValid
                                || !hasUnsavedChanges
                        )
                    }
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(isSaving || hasUnsavedChanges)
        .task(id: selectedCirclePhoto) {
            guard let selectedCirclePhoto else { return }
            isPreparingCirclePhoto = true
            defer { isPreparingCirclePhoto = false }
            do {
                guard let data = try await selectedCirclePhoto.loadTransferable(type: Data.self) else { return }
                pendingCirclePhotoResize = try PendingPhotoResize(data: data)
            } catch {
                model.message = "Couldn’t prepare that circle photo: \(error.localizedDescription)"
            }
        }
        .sheet(item: $pendingCirclePhotoResize, onDismiss: { selectedCirclePhoto = nil }) { photo in
            PhotoResizeEditor(
                title: "Resize circle photo",
                photo: photo,
                onCancel: { pendingCirclePhotoResize = nil },
                onUsePhoto: { url in
                    pendingCirclePhotoURL = url
                    circlePhotoChanged = true
                    pendingCirclePhotoResize = nil
                }
            )
        }
        .sheet(isPresented: $showingOwnershipTransfer) {
            OwnershipTransferView(
                members: circle.members.filter { $0.id != model.currentUser?.id },
                isPresented: $showingOwnershipTransfer,
                closeSettings: { isPresented = false }
            )
        }
        .alert(
            "Discard unsaved changes?",
            isPresented: $showingDiscardChangesConfirmation
        ) {
            Button("Keep Editing", role: .cancel) {}
            Button("Discard Changes", role: .destructive) { isPresented = false }
        } message: {
            Text("Your circle settings and photo changes will not be saved.")
        }
        .confirmationDialog(
            "Regenerate the code for \(circle.name)?",
            isPresented: $showingCodeRegenerationConfirmation,
            titleVisibility: .visible
        ) {
            Button("Regenerate code", role: .destructive) {
                isRegeneratingCode = true
                Task {
                    _ = await model.regenerateCurrentCircleInviteCode()
                    isRegeneratingCode = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Anyone using the previous code will no longer be able to join. Current members are not affected.")
        }
        .confirmationDialog(
            "Notify everyone in \(circle.name)?",
            isPresented: $showingForcePromptConfirmation,
            titleVisibility: .visible
        ) {
            Button("Force blessing now", role: .destructive) {
                Task {
                    if await model.forceCurrentCirclePrompt() { isPresented = false }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.usesAuthentication
                 ? "This restarts today’s response window and contacts every registered device in this circle."
                 : "This restarts today’s local demo response window.")
        }
        .confirmationDialog(
            "Leave \(circle.name)?",
            isPresented: $showingLeaveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Leave circle", role: .destructive) {
                isLeaving = true
                Task {
                    if await model.leaveCurrentCircle() { isPresented = false }
                    isLeaving = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(isOwner && circle.members.count == 1
                 ? "This circle has no other members and will be permanently deleted."
                 : "You can only rejoin later with a valid invite code.")
        }
        .confirmationDialog(
            "Remove \(memberToRemove?.displayName ?? "this member")?",
            isPresented: Binding(
                get: { memberToRemove != nil },
                set: { if !$0 { memberToRemove = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let memberToRemove {
                Button("Remove member", role: .destructive) {
                    isRemovingMember = true
                    Task {
                        _ = await model.removeMemberFromCurrentCircle(memberToRemove.id)
                        isRemovingMember = false
                        self.memberToRemove = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) { memberToRemove = nil }
        } message: {
            Text("They will lose access immediately. Their existing blessing history remains visible to current circle members.")
        }
    }

    private var photoPreviewCircle: CircleGroup {
        var preview = model.circle ?? circle
        preview.photoURL = pendingCirclePhotoURL
        return preview
    }

    private func saveChanges() async {
        isSaving = true
        defer { isSaving = false }
        let settingsSaved = await model.updateCircleSettings(
            name: name,
            timeZoneIdentifier: timeZoneIdentifier,
            randomWindowStartMinutes: randomWindowStartMinutes,
            randomWindowEndMinutes: randomWindowEndMinutes,
            responseWindowMinutes: selectedMinutes,
            allowsLateBlessings: allowsLateBlessings,
            repeatWindowMinutes: repeatWindowMinutes,
            endOfDayMinutes: endOfDayMinutes
        )
        guard settingsSaved else { return }
        if circlePhotoChanged {
            guard await model.updateCirclePhoto(pendingCirclePhotoURL) else { return }
        }
        isPresented = false
    }

    private var timeZoneDisplayName: String {
        guard let zone = TimeZone(identifier: timeZoneIdentifier) else { return timeZoneIdentifier }
        return zone.localizedName(for: .standard, locale: .current) ?? timeZoneIdentifier
    }

    private var currentInviteCode: String {
        model.circle?.id == circle.id ? (model.circle?.inviteCode ?? "") : circle.inviteCode
    }

    private var inviteURL: URL {
        CircleInviteLink.webURL(for: currentInviteCode) ?? CircleInviteLink.websiteURL
    }

    private static func wallClockDate(minutes: Int) -> Date {
        Calendar.current.date(
            from: DateComponents(year: 2001, month: 1, day: 1, hour: minutes / 60, minute: minutes % 60)
        ) ?? .now
    }

    private static func minutes(from date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private static func durationLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        if minutes % 60 == 0 {
            let hours = minutes / 60
            return hours == 1 ? "1 hour" : "\(hours) hours"
        }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}

private struct OwnershipTransferView: View {
    @Environment(AppModel.self) private var model
    let members: [Member]
    @Binding var isPresented: Bool
    let closeSettings: () -> Void
    @State private var candidate: Member?
    @State private var isTransferring = false

    var body: some View {
        NavigationStack {
            List(members) { member in
                Button {
                    candidate = member
                } label: {
                    HStack(spacing: 12) {
                        AvatarBadge(member: member, size: 42)
                        Text(member.displayName)
                            .foregroundStyle(AppTheme.ink)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryInk)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                }
                .disabled(isTransferring)
            }
            .navigationTitle("Choose new owner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                        .disabled(isTransferring)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .confirmationDialog(
            "Transfer ownership to \(candidate?.displayName ?? "this member")?",
            isPresented: Binding(
                get: { candidate != nil },
                set: { if !$0 { candidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let candidate {
                Button("Transfer ownership") {
                    isTransferring = true
                    Task {
                        if await model.transferCurrentCircleOwnership(to: candidate.id) {
                            isPresented = false
                            closeSettings()
                        }
                        isTransferring = false
                        self.candidate = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) { candidate = nil }
        } message: {
            Text("You will remain in the circle, but only the new owner will be able to change its settings.")
        }
    }
}

private struct CircleTimeZonePicker: View {
    @Binding var selection: String
    @State private var searchText = ""

    private var zones: [String] {
        let all = TimeZone.knownTimeZoneIdentifiers
        guard !searchText.isEmpty else { return all }
        return all.filter { identifier in
            identifier.localizedCaseInsensitiveContains(searchText)
                || displayName(for: identifier).localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List(zones, id: \.self) { identifier in
            Button {
                selection = identifier
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName(for: identifier))
                            .foregroundStyle(AppTheme.ink)
                        Text(identifier)
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryInk)
                    }
                    Spacer()
                    if selection == identifier {
                        Image(systemName: "checkmark")
                            .foregroundStyle(AppTheme.primary)
                            .accessibilityLabel("Selected")
                    }
                }
            }
        }
        .navigationTitle("Circle time zone")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "City or time zone")
    }

    private func displayName(for identifier: String) -> String {
        TimeZone(identifier: identifier)?.localizedName(for: .standard, locale: .current) ?? identifier
    }
}
