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
                    biblePreference
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

            if model.circle?.ownerID == model.currentUser?.id {
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
        }
    }

    private var biblePreference: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Your Bible version", systemImage: "book.closed")
                .font(.headline)
            Picker(
                "Bible version",
                selection: Binding(
                    get: { model.selectedBibleTranslation.id },
                    set: { versionID in Task { await model.updateBibleVersion(versionID) } }
                )
            ) {
                ForEach(model.bibleTranslations) { translation in
                    Text("\(translation.shortName) — \(translation.name)")
                        .tag(translation.id)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            Text("Scripture references from everyone are rendered in this version. Public-domain translations are available.")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryInk)
        }
        .blessingCard()
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
    @State private var isSaving = false

    init(circle: CircleGroup, isPresented: Binding<Bool>) {
        self.circle = circle
        _isPresented = isPresented
        let index = ResponseWindowOptions.minutes.firstIndex(of: circle.responseWindowMinutes) ?? 4
        _selectedIndex = State(initialValue: Double(index))
        _allowsLateBlessings = State(initialValue: circle.allowsLateBlessings)
    }

    private var selectedMinutes: Int {
        let index = min(max(Int(selectedIndex.rounded()), 0), ResponseWindowOptions.minutes.count - 1)
        return ResponseWindowOptions.minutes[index]
    }

    var body: some View {
        NavigationStack {
            Form {
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

                        Text("Choose 1, 2, 3, 5, 10, 15, 20, 40, 60, 90, 120, or 180 minutes.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryInk)
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
                    Button {
                        isSaving = true
                        Task {
                            let saved = await model.updateCircleSettings(
                                responseWindowMinutes: selectedMinutes,
                                allowsLateBlessings: allowsLateBlessings
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
                    .disabled(isSaving)
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
    }
}
