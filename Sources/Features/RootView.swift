import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.loadState {
            case .idle, .loading:
                LoadingView()
            case .ready:
                MainTabView()
            case .signedOut:
                SignInView()
            case let .failed(message):
                ContentUnavailableView(
                    "Couldn’t open your circle",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            }
        }
        .task { await model.bootstrap() }
        .alert(
            "Blessing Circle",
            isPresented: Binding(
                get: { model.message != nil },
                set: { if !$0 { model.message = nil } }
            )
        ) {
            Button("OK") { model.message = nil }
        } message: {
            Text(model.message ?? "")
        }
        .onOpenURL { url in
            Task { await model.handleDeepLink(url) }
        }
        .preferredColorScheme(preferredColorScheme)
    }

    private var preferredColorScheme: ColorScheme? {
        switch model.appearancePreference {
        case .automatic: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

private struct LoadingView: View {
    var body: some View {
        ZStack {
            AppTheme.canvas.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(AppTheme.iris)
                    .accessibilityHidden(true)
                Text("Gathering your circle")
                    .font(.title3.weight(.semibold))
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Loading")
            }
        }
    }
}

struct MainTabView: View {
    @Environment(AppModel.self) private var model
    @State private var showingUserSettings = false

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            NavigationStack {
                TodayView()
                    .toolbar { GlobalAppToolbar(showingUserSettings: $showingUserSettings) }
            }
            .tabItem { Label("Today", systemImage: "sun.max") }
            .tag(0)

            NavigationStack {
                CircleTimelineView()
                    .toolbar { GlobalAppToolbar(showingUserSettings: $showingUserSettings) }
            }
            .tabItem { Label("Timeline", systemImage: "point.3.connected.trianglepath.dotted") }
            .tag(1)

            NavigationStack {
                CircleView()
                    .toolbar { GlobalAppToolbar(showingUserSettings: $showingUserSettings) }
            }
            .tabItem { Label("Circle", systemImage: "person.3") }
            .tag(2)
        }
        .sheet(isPresented: $model.isCapturePresented) {
            CaptureView()
                .presentationDetents([.large])
                .interactiveDismissDisabled(model.isSubmitting)
        }
        .sheet(isPresented: $showingUserSettings) {
            UserSettingsView(isPresented: $showingUserSettings)
        }
        .sheet(item: $model.deepLinkedBlessing) { item in
            BlessingDetailView(
                member: item.member,
                blessing: item.blessing,
                allowsResponses: model.canRespond(to: item.blessing)
            )
        }
        .sensoryFeedback(.success, trigger: model.hasSubmittedToday)
    }
}

private struct GlobalAppToolbar: ToolbarContent {
    @Environment(AppModel.self) private var model
    @Binding var showingUserSettings: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Button {
                    showingUserSettings = true
                } label: {
                    Label("User settings", systemImage: "person.crop.circle")
                }

                Button {
                    model.selectedTab = 2
                } label: {
                    Label("Manage circles", systemImage: "person.3")
                }

                if model.usesAuthentication {
                    Divider()
                    Button("Sign out", role: .destructive) {
                        Task { await model.signOut() }
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("App menu")
        }

        ToolbarItem(placement: .principal) {
            Menu {
                if model.circles.isEmpty {
                    Text("No circles yet")
                } else {
                    ForEach(model.circles) { circle in
                        Button {
                            Task { await model.switchCircle(to: circle.id) }
                        } label: {
                            if model.circle?.id == circle.id {
                                Label(circle.name, systemImage: "checkmark")
                            } else {
                                Text(circle.name)
                            }
                        }
                    }
                }

                Divider()
                Button {
                    model.selectedTab = 2
                } label: {
                    Label("Join or create a circle", systemImage: "plus.circle")
                }
            } label: {
                HStack(spacing: 5) {
                    if model.isSwitchingCircle {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(model.circle?.name ?? "Choose circle")
                        .font(.headline)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .frame(minHeight: 44)
            }
            .accessibilityLabel("Current circle, \(model.circle?.name ?? "none")")
            .accessibilityHint("Opens the circle switcher")
        }
    }
}

private struct UserSettingsView: View {
    @Environment(AppModel.self) private var model
    @Binding var isPresented: Bool

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                if let user = model.currentUser {
                    Section("Account") {
                        LabeledContent("Name", value: user.displayName)
                    }
                }

                Section {
                    Picker(
                        "Bible version",
                        selection: Binding(
                            get: { model.selectedBibleTranslation.id },
                            set: { versionID in Task { await model.updateBibleVersion(versionID) } }
                        )
                    ) {
                        ForEach(model.bibleTranslationGroups) { group in
                            Section(group.languageName) {
                                ForEach(group.translations) { translation in
                                    Text("\(translation.shortName) — \(translation.name)")
                                        .tag(translation.id)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Scripture")
                } footer: {
                    Text("Every tagged passage is displayed in this public-domain translation, regardless of which circle it came from.")
                }

                Section("Appearance") {
                    Picker("Appearance", selection: Binding(
                        get: { model.appearancePreference },
                        set: { model.appearancePreference = $0 }
                    )) {
                        ForEach(AppearancePreference.allCases) { preference in
                            Label(preference.title, systemImage: preference.systemImage)
                                .tag(preference)
                        }
                    }
                    .pickerStyle(.inline)
                }

                Section {
                    Picker("Refresh interval", selection: $model.widgetRefreshMinutes) {
                        ForEach(AppModel.widgetRefreshOptions, id: \.self) { minutes in
                            Text(minutes < 60 ? "\(minutes) minutes" : "\(minutes / 60) hours")
                                .tag(minutes)
                        }
                    }
                } header: {
                    Text("Home Screen Widget")
                } footer: {
                    Text("Blessings rotate at about this interval when no circle is waiting for your response. iOS may refresh less often to preserve battery life.")
                }
            }
            .navigationTitle("User settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isPresented = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
