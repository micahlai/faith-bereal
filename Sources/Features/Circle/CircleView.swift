import SwiftUI

struct CircleView: View {
    @Environment(AppModel.self) private var model
    @State private var joinCode = ""
    @State private var newCircleName = ""
    @State private var showingJoin = false
    @State private var showingCreate = false
    @State private var showingSettings = false

    var body: some View {
        ZStack {
            AppTheme.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    circleHeader
                    members
                    actions
                }
                .frame(maxWidth: 680)
                .padding(AppTheme.pagePadding)
                .padding(.bottom, 100)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Circle")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingJoin) { joinSheet }
        .sheet(isPresented: $showingCreate) { createSheet }
        .sheet(isPresented: $showingSettings) {
            if let circle = model.circle {
                CircleSettingsView(circle: circle, isPresented: $showingSettings)
            }
        }
    }

    private var circleHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(AppTheme.iris)
                    .accessibilityHidden(true)
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
                ShareLink(item: model.circle?.inviteCode ?? "") {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(minHeight: 44)
                }
                .disabled(model.circle == nil)
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
            }
            .buttonStyle(.plain)
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
                Label("Join another circle", systemImage: "person.badge.plus")
                    .frame(maxWidth: .infinity, minHeight: AppTheme.controlHeight)
            }
            .buttonStyle(.borderedProminent)
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
        NavigationStack {
            Form {
                Section("Circle name") {
                    TextField("Sunday Table", text: $newCircleName)
                        .textContentType(.organizationName)
                }
                Section {
                    Button("Create circle") {
                        Task {
                            if await model.createCircle(name: newCircleName) { showingCreate = false }
                        }
                    }
                    .disabled(newCircleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("New circle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingCreate = false } }
            }
        }
        .presentationDetents([.medium])
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
    @State private var isSaving = false
    @State private var isLeaving = false
    @State private var showingLeaveConfirmation = false
    @State private var showingOwnershipTransfer = false
    @State private var memberToRemove: Member?
    @State private var isRemovingMember = false

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
    }

    private var selectedMinutes: Int {
        let index = min(max(Int(selectedIndex.rounded()), 0), ResponseWindowOptions.minutes.count - 1)
        return ResponseWindowOptions.minutes[index]
    }

    private var randomWindowStartMinutes: Int { Self.minutes(from: randomWindowStart) }
    private var randomWindowEndMinutes: Int { Self.minutes(from: randomWindowEnd) }
    private var settingsAreValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && randomWindowEndMinutes > randomWindowStartMinutes
    }
    private var isOwner: Bool { model.circle?.ownerID == model.currentUser?.id }

    var body: some View {
        NavigationStack {
            Form {
                if isOwner {
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
                                    .foregroundStyle(AppTheme.iris)
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
                            .tint(AppTheme.iris)
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

                    Section {
                        Button {
                            isSaving = true
                            Task {
                                let saved = await model.updateCircleSettings(
                                    name: name,
                                    timeZoneIdentifier: timeZoneIdentifier,
                                    randomWindowStartMinutes: randomWindowStartMinutes,
                                    randomWindowEndMinutes: randomWindowEndMinutes,
                                    responseWindowMinutes: selectedMinutes,
                                    allowsLateBlessings: allowsLateBlessings,
                                    repeatWindowMinutes: repeatWindowMinutes
                                )
                                isSaving = false
                                if saved { isPresented = false }
                            }
                        } label: {
                            HStack {
                                Text("Save settings")
                                Spacer()
                                if isSaving { ProgressView() }
                            }
                        }
                        .disabled(isSaving || !settingsAreValid)
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
                    Button("Cancel") { isPresented = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $showingOwnershipTransfer) {
            OwnershipTransferView(
                members: circle.members.filter { $0.id != model.currentUser?.id },
                isPresented: $showingOwnershipTransfer,
                closeSettings: { isPresented = false }
            )
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
                            .foregroundStyle(AppTheme.iris)
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
