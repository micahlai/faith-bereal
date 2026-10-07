import SwiftUI
import PhotosUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.loadState {
            case .idle, .loading:
                LoadingView()
            case .ready:
                if !model.hasSeenAbout {
                    AboutView { model.hasSeenAbout = true }
                } else if !model.hasChosenInitialAppearance {
                    AppearanceOnboardingView { model.hasChosenInitialAppearance = true }
                } else if model.circles.isEmpty {
                    EmptyCircleShell()
                } else {
                    MainTabView()
                }
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
            "manna circle",
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

private struct EmptyCircleShell: View {
    @State private var showingUserSettings = false
    @State private var showingAbout = false

    var body: some View {
        NavigationStack {
            CircleView()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button("About manna circle", systemImage: "info.circle") { showingAbout = true }
                            Button("User settings", systemImage: "person.crop.circle") { showingUserSettings = true }
                        } label: {
                            Image(systemName: "line.3.horizontal").frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityLabel("App menu")
                    }
                }
        }
        .sheet(isPresented: $showingUserSettings) { UserSettingsView(isPresented: $showingUserSettings) }
        .sheet(isPresented: $showingAbout) { AboutView(showsDismissButton: true) { showingAbout = false } }
    }
}

private struct AboutView: View {
    var showsDismissButton = false
    let onContinue: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 28) {
                        Image(systemName: "circle.hexagongrid.fill")
                            .font(.system(size: 72, weight: .light))
                            .foregroundStyle(AppTheme.primary)
                        VStack(spacing: 8) {
                            Text("manna circle")
                                .font(.system(.largeTitle, design: .serif, weight: .bold))
                            Text("daily blessings, shared together")
                                .font(.title3)
                                .foregroundStyle(AppTheme.secondaryInk)
                        }
                        VStack(alignment: .leading, spacing: 20) {
                            aboutPoint("sun.haze", "About manna circle", "A friend told me that one of his prayer requests was to count his blessings from God throughout the day more. 1 John 1:7 tells us that our faith with God is meant to be shared, thus let's share our daily bread with each other throughout our day.")
                            aboutPoint("bell.badge", "How does it work?", "Each circle receives one daily blessing time, wherever its members are. At that random time, everyone in the circle can share one thing on how God has blessed their day in the form of text, audio, or video.")
                        }
                        .blessingCard()
                        Button(showsDismissButton ? "Done" : "Continue") { onContinue() }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity, minHeight: AppTheme.controlHeight)
                    }
                    .frame(maxWidth: 620)
                    .padding(AppTheme.pagePadding)
                }
            }
            .navigationTitle(showsDismissButton ? "About" : "")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func aboutPoint(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.title2).foregroundStyle(AppTheme.primary).frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(AppTheme.secondaryInk)
            }
        }
    }
}

private struct AppearanceOnboardingView: View {
    @Environment(AppModel.self) private var model
    let onContinue: () -> Void

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            ZStack {
                AppTheme.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Make it feel at home")
                                .font(.system(.largeTitle, design: .serif, weight: .bold))
                            Text("Choose how manna circle looks on screen and on your Home Screen. You can change both anytime in User settings.")
                                .foregroundStyle(AppTheme.secondaryInk)
                        }
                        Picker("Appearance", selection: $model.appearancePreference) {
                            ForEach(AppearancePreference.allCases) { preference in
                                Label(preference.title, systemImage: preference.systemImage).tag(preference)
                            }
                        }
                        .pickerStyle(.inline)
                        .blessingCard()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("App icon")
                                .font(.headline)
                            AppIconChoiceGrid()

                            if model.isChangingAppIcon {
                                HStack {
                                    ProgressView()
                                    Text("Changing app icon…")
                                        .font(.subheadline)
                                        .foregroundStyle(AppTheme.secondaryInk)
                                }
                            }
                            Text("Automatic follows the Home Screen appearance. Cream and Midnight keep one logo style.")
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryInk)
                        }
                        .blessingCard()

                        Button("Continue") { onContinue() }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity, minHeight: AppTheme.controlHeight)
                            .disabled(model.isChangingAppIcon)
                    }
                    .frame(maxWidth: 620)
                    .padding(AppTheme.pagePadding)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private struct AppIconChoiceGrid: View {
    @Environment(AppModel.self) private var model
    private let columns = [GridItem(.adaptive(minimum: 112), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(AppIconPreference.allCases) { preference in
                let isSelected = model.appIconPreference == preference
                Button {
                    Task { await model.updateAppIcon(preference) }
                } label: {
                    VStack(spacing: 10) {
                        AppIconPreview(preference: preference)
                            .frame(height: 78)
                        HStack(spacing: 5) {
                            Text(preference.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(AppTheme.primary)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, minHeight: 132)
                    .background(AppTheme.canvas, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isSelected ? AppTheme.primary : AppTheme.divider, lineWidth: isSelected ? 3 : 1)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(model.isChangingAppIcon)
                .accessibilityLabel("\(preference.title) app icon")
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

private struct AppIconPreview: View {
    let preference: AppIconPreference
    private let cream = Color(red: 0.98, green: 0.95, blue: 0.86)
    private let charcoal = Color(red: 0.08, green: 0.07, blue: 0.07)
    private let orange = Color(red: 0.69, green: 0.36, blue: 0.13)

    var body: some View {
        switch preference {
        case .automatic:
            HStack(spacing: 6) {
                logoTile(background: cream, foreground: charcoal)
                logoTile(background: charcoal, foreground: cream)
            }
        case .cream:
            logoTile(background: cream, foreground: charcoal)
        case .midnight:
            logoTile(background: charcoal, foreground: cream)
        }
    }

    private func logoTile(background: Color, foreground: Color) -> some View {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(background)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                HStack(spacing: 0) {
                    Text("m")
                        .foregroundStyle(foreground)
                    Text(".")
                        .foregroundStyle(orange)
                }
                .font(.system(size: 31, weight: .bold, design: .serif))
                .minimumScaleFactor(0.65)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

private struct LoadingView: View {
    var body: some View {
        ZStack {
            AppTheme.canvas.ignoresSafeArea()
            VStack(spacing: 18) {
                Image("MannaWordmark")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 280)
                    .accessibilityLabel("manna")
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
    @State private var showingAbout = false

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            NavigationStack {
                TodayView()
                    .toolbar { GlobalAppToolbar(showingUserSettings: $showingUserSettings, showingAbout: $showingAbout) }
            }
            .tabItem { Label("Today", systemImage: "sun.max") }
            .tag(0)

            NavigationStack {
                CircleTimelineView()
                    .toolbar { GlobalAppToolbar(showingUserSettings: $showingUserSettings, showingAbout: $showingAbout) }
            }
            .tabItem { Label("Timeline", systemImage: "point.3.connected.trianglepath.dotted") }
            .tag(1)

            NavigationStack {
                CircleView()
                    .toolbar { GlobalAppToolbar(showingUserSettings: $showingUserSettings, showingAbout: $showingAbout) }
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
        .sheet(isPresented: $showingAbout) { AboutView(showsDismissButton: true) { showingAbout = false } }
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
    @Binding var showingAbout: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Button {
                    showingAbout = true
                } label: {
                    Label("About manna circle", systemImage: "info.circle")
                }
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
                            HStack(spacing: 10) {
                                circleSwitcherIcon(size: 30)
                                Text(circle.name)
                                if model.circle?.id == circle.id {
                                    Image(systemName: "checkmark")
                                }
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
                    } else if model.circle != nil {
                        circleSwitcherIcon(size: 26)
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

    private func circleSwitcherIcon(size: CGFloat) -> some View {
        Image(systemName: "person.3.fill")
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(AppTheme.primary.gradient)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

private struct UserSettingsView: View {
    @Environment(AppModel.self) private var model
    @Binding var isPresented: Bool
    @State private var showingProfileEditor = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                if let user = model.currentUser {
                    Section("Account") {
                        Button { showingProfileEditor = true } label: {
                            HStack(spacing: 12) {
                                AvatarBadge(member: user, size: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(user.displayName).foregroundStyle(AppTheme.ink)
                                    Text("Edit name and photo")
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.secondaryInk)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !model.circles.isEmpty {
                    Section {
                        ForEach(model.circles) { circle in
                            Toggle(
                                isOn: Binding(
                                    get: {
                                        model.circles
                                            .first(where: { $0.id == circle.id })?
                                            .circleActivityNotificationsEnabled ?? true
                                    },
                                    set: { enabled in
                                        Task { await model.setCircleActivityNotifications(enabled, for: circle.id) }
                                    }
                                )
                            ) {
                                HStack(spacing: 12) {
                                    CircleAvatarBadge(circle: circle, size: 38)
                                    Text(circle.name)
                                        .foregroundStyle(AppTheme.ink)
                                }
                            }
                            .frame(minHeight: 44)
                        }
                    } header: {
                        Text("Circle notifications")
                    } footer: {
                        Text("Choose which circles can notify you when someone shares a blessing or adds a response to a blessing you follow.")
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

                Section {
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

                    Picker(
                        "App icon",
                        selection: Binding(
                            get: { model.appIconPreference },
                            set: { preference in
                                Task { await model.updateAppIcon(preference) }
                            }
                        )
                    ) {
                        ForEach(AppIconPreference.allCases) { preference in
                            Label(preference.title, systemImage: preference.systemImage)
                                .tag(preference)
                        }
                    }
                    .disabled(model.isChangingAppIcon)

                    if model.isChangingAppIcon {
                        HStack {
                            ProgressView()
                            Text("Changing app icon…")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Automatic lets iOS use the cream or midnight manna icon with the Home Screen appearance. Choose one to keep that logo all the time.")
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
        .sheet(isPresented: $showingProfileEditor) {
            if let user = model.currentUser {
                ProfileEditorView(user: user, isPresented: $showingProfileEditor)
            }
        }
    }
}

private struct ProfileEditorView: View {
    @Environment(AppModel.self) private var model
    let user: Member
    @Binding var isPresented: Bool
    @State private var displayName: String
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoURL: URL?
    @State private var isSaving = false
    @State private var isPreparingPhoto = false

    init(user: Member, isPresented: Binding<Bool>) {
        self.user = user
        _isPresented = isPresented
        _displayName = State(initialValue: user.displayName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            avatarPreview
                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                Label("Choose photo", systemImage: "photo")
                                    .frame(minHeight: 44)
                            }
                            if isPreparingPhoto {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("Preparing photo…")
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.secondaryInk)
                                }
                            }
                        }
                        Spacer()
                    }
                }
                Section("Name") {
                    TextField("Your name", text: $displayName)
                        .textContentType(.name)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        Task {
                            isSaving = true
                            if await model.updateProfile(displayName: displayName, avatarURL: photoURL) {
                                isPresented = false
                            }
                            isSaving = false
                        }
                    }
                    .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving || isPreparingPhoto)
                }
            }
            .task(id: selectedPhoto) {
                guard let selectedPhoto else { return }
                isPreparingPhoto = true
                defer { isPreparingPhoto = false }
                do {
                    guard let data = try await selectedPhoto.loadTransferable(type: Data.self) else { return }
                    photoURL = try CaptureMediaStore.persistProfilePhoto(data: data)
                } catch {
                    model.message = "Couldn’t prepare that photo: \(error.localizedDescription)"
                }
            }
        }
    }

    @ViewBuilder private var avatarPreview: some View {
        if let photoURL {
            AsyncImage(url: photoURL) { image in image.resizable().scaledToFill() } placeholder: { ProgressView() }
                .frame(width: 96, height: 96)
                .clipShape(Circle())
        } else {
            AvatarBadge(member: user, size: 96)
        }
    }
}
