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
                if !model.hasSeenAbout || !model.hasChosenInitialAppearance {
                    StartupOnboardingView(
                        initialPage: model.hasSeenAbout ? .appearance : .about
                    ) {
                        model.hasSeenAbout = true
                        model.hasChosenInitialAppearance = true
                    }
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
    @State private var showingHelp = false

    var body: some View {
        NavigationStack {
            CircleView()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button("Help", systemImage: "questionmark.circle") { showingHelp = true }
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
        .sheet(isPresented: $showingHelp) { HelpView() }
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
                        AboutPageContent()
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
}

private struct AboutPageContent: View {
    var body: some View {
        VStack(spacing: 28) {
            Image("MannaWordmark")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 280)
                .accessibilityLabel("manna")
            VStack(spacing: 8) {
                Text("circle")
                    .font(.system(.largeTitle, design: .serif, weight: .regular))
                Text("daily blessings, shared together")
                    .font(.title3)
                    .foregroundStyle(AppTheme.secondaryInk)
            }
            VStack(alignment: .leading, spacing: 20) {
                aboutPoint("sun.haze", "About manna circle", "A friend told me that one of his prayer requests was to count his blessings from God throughout the day more. 1 John 1:7 tells us that our faith with God is meant to be shared, thus let's share our daily bread with each other throughout our day.")
                aboutPoint("bell.badge", "How does it work?", "Each circle receives one daily blessing time, wherever its members are. At that random time, everyone in the circle can share one thing on how God has blessed their day in the form of text, audio, or video.")
            }
            .blessingCard()
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

private enum StartupOnboardingPage: Int, CaseIterable {
    case about
    case appearance
    case appIcon
    case widget

    var title: String {
        switch self {
        case .about: "Welcome"
        case .appearance: "Appearance"
        case .appIcon: "App icon"
        case .widget: "Widget"
        }
    }

    var stepNumber: Int { rawValue + 1 }
}

private struct StartupOnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: StartupOnboardingPage
    let onFinished: () -> Void

    init(initialPage: StartupOnboardingPage, onFinished: @escaping () -> Void) {
        _page = State(initialValue: initialPage)
        self.onFinished = onFinished
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            ZStack {
                AppTheme.canvas.ignoresSafeArea()
                VStack(spacing: 0) {
                    StartupProgressHeader(page: page)
                    ScrollView {
                        pageContent(appearancePreference: $model.appearancePreference)
                            .frame(maxWidth: 620, alignment: .leading)
                            .padding(AppTheme.pagePadding)
                            .frame(maxWidth: .infinity)
                            .id(page)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                navigationControls
            }
            .navigationTitle(page.title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func pageContent(appearancePreference: Binding<AppearancePreference>) -> some View {
        switch page {
        case .about:
            AboutPageContent()
        case .appearance:
            AppearanceOnboardingPage(selection: appearancePreference)
        case .appIcon:
            AppIconOnboardingPage()
        case .widget:
            WidgetOnboardingPage()
        }
    }

    private var navigationControls: some View {
        HStack(spacing: 12) {
            if page != .about {
                Button { move(to: page.rawValue - 1) } label: {
                    Text("Back")
                        .frame(minWidth: 64, minHeight: AppTheme.controlHeight)
                }
                    .buttonStyle(.bordered)
            }
            Spacer(minLength: 12)
            Button {
                if page == .widget {
                    onFinished()
                } else {
                    move(to: page.rawValue + 1)
                }
            } label: {
                Text("Continue")
                    .frame(minWidth: 104, minHeight: AppTheme.controlHeight)
            }
            .buttonStyle(.borderedProminent)
            .disabled(page == .appIcon && model.isChangingAppIcon)
        }
        .frame(maxWidth: 620)
        .padding(.horizontal, AppTheme.pagePadding)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func move(to rawValue: Int) {
        guard let nextPage = StartupOnboardingPage(rawValue: rawValue) else { return }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
            page = nextPage
        }
    }
}

private struct StartupProgressHeader: View {
    let page: StartupOnboardingPage

    var body: some View {
        VStack(spacing: 7) {
            ProgressView(
                value: Double(page.stepNumber),
                total: Double(StartupOnboardingPage.allCases.count)
            )
            .tint(AppTheme.primary)
            Text("Step \(page.stepNumber) of \(StartupOnboardingPage.allCases.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryInk)
        }
        .padding(.horizontal, AppTheme.pagePadding)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(page.stepNumber) of \(StartupOnboardingPage.allCases.count), \(page.title)")
    }
}

private struct AppearanceOnboardingPage: View {
    @Binding var selection: AppearancePreference

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            onboardingHeading(
                "Make it feel at home",
                "Choose how manna circle looks on screen. You can change this anytime in User settings."
            )
            Picker("Appearance", selection: $selection) {
                ForEach(AppearancePreference.allCases) { preference in
                    Label(preference.title, systemImage: preference.systemImage).tag(preference)
                }
            }
            .pickerStyle(.inline)
            .blessingCard()
        }
    }
}

private struct AppIconOnboardingPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            onboardingHeading(
                "Choose your manna icon",
                "Pick the logo you want on your Home Screen. Automatic follows your device appearance."
            )
            AppIconChoiceGrid()
            if model.isChangingAppIcon {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Changing app icon…")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryInk)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct WidgetOnboardingPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            onboardingHeading(
                "Add manna to your Home Screen",
                "The widget takes you straight to Today when it is time to share. At other times, it gently rotates recent blessings from your circles."
            )
            WidgetOnboardingPreview()
            VStack(alignment: .leading, spacing: 18) {
                instructionRow(1, "Touch and hold an empty area on your Home Screen.")
                instructionRow(2, "Tap Edit, then Add Widget.")
                instructionRow(3, "Search for “manna circle,” choose a size, and add it.")
            }
            .blessingCard()
            Text("You can continue without adding it and follow these same steps whenever you’re ready.")
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryInk)
        }
    }

    private func instructionRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(AppTheme.primary, in: Circle())
                .accessibilityHidden(true)
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number). \(text)")
    }
}

private struct WidgetOnboardingPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your circle")
                        .font(.headline)
                    Text("Time to share a blessing")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryInk)
                }
                Spacer()
                Image("MannaWordmark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 74)
                    .accessibilityHidden(true)
            }
            Text("What has blessed you today?")
                .font(.title3.weight(.semibold))
            Label("Opens Today", systemImage: "arrow.up.forward.app")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.primary)
        }
        .padding(18)
        .frame(maxWidth: 330, minHeight: 168, alignment: .leading)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AppTheme.divider, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Example manna circle widget. Your circle. Time to share a blessing. What has blessed you today? Opens Today.")
    }
}

private func onboardingHeading(_ title: String, _ detail: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Text(title)
            .font(.system(.largeTitle, design: .serif, weight: .bold))
        Text(detail)
            .foregroundStyle(AppTheme.secondaryInk)
    }
}

private struct AppIconChoiceGrid: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 12) {
            ForEach(AppIconPreference.allCases) { preference in
                let isSelected = model.appIconPreference == preference
                Button {
                    Task { await model.updateAppIcon(preference) }
                } label: {
                    Group {
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(spacing: 14) {
                                AppIconPreview(preference: preference)
                                choiceText(preference, isSelected: isSelected)
                            }
                        } else {
                            HStack(spacing: 16) {
                                AppIconPreview(preference: preference)
                                    .frame(width: 154)
                                choiceText(preference, isSelected: isSelected)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, minHeight: 124)
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(isSelected ? AppTheme.primary : AppTheme.divider, lineWidth: isSelected ? 3 : 1)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(model.isChangingAppIcon)
                .accessibilityIdentifier("onboarding-icon-\(preference.rawValue)")
                .accessibilityLabel("\(preference.title) app icon")
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
                .accessibilityHint(preference.detail)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private func choiceText(_ preference: AppIconPreference, isSelected: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(preference.title)
                    .font(.headline)
                Text(preference.detail)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryInk)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 8)
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(isSelected ? AppTheme.primary : AppTheme.secondaryInk)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension AppIconPreference {
    var detail: String {
        switch self {
        case .automatic: "Matches your device appearance"
        case .cream: "Warm cream background"
        case .midnight: "Deep charcoal background"
        }
    }
}

private struct AppIconPreview: View {
    let preference: AppIconPreference

    var body: some View {
        Group {
            switch preference {
            case .automatic:
                HStack(spacing: 8) {
                    iconImage("MannaIconCream")
                    iconImage("MannaIconMidnight")
                }
            case .cream:
                iconImage("MannaIconCream")
            case .midnight:
                iconImage("MannaIconMidnight")
            }
        }
        .frame(height: 88)
        .accessibilityHidden(true)
    }

    private func iconImage(_ name: String) -> some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            }
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
    @State private var showingHelp = false

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            NavigationStack {
                TodayView()
                    .toolbar { GlobalAppToolbar(showingUserSettings: $showingUserSettings, showingAbout: $showingAbout, showingHelp: $showingHelp) }
            }
            .tabItem { Label("Today", systemImage: "sun.max") }
            .tag(0)

            NavigationStack {
                CircleTimelineView()
                    .toolbar { GlobalAppToolbar(showingUserSettings: $showingUserSettings, showingAbout: $showingAbout, showingHelp: $showingHelp) }
            }
            .tabItem { Label("Timeline", systemImage: "point.3.connected.trianglepath.dotted") }
            .tag(1)

            NavigationStack {
                CircleView()
                    .toolbar { GlobalAppToolbar(showingUserSettings: $showingUserSettings, showingAbout: $showingAbout, showingHelp: $showingHelp) }
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
        .sheet(isPresented: $showingHelp) { HelpView() }
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
    @Binding var showingHelp: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Button("Help", systemImage: "questionmark.circle") { showingHelp = true }
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
                            HStack {
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
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 12) {
                                    CircleAvatarBadge(circle: circle, size: 38)
                                    Text(circle.name)
                                        .font(.headline)
                                        .foregroundStyle(AppTheme.ink)
                                }
                                Toggle(
                                    "Blessings and responses",
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
                                )
                                Toggle(
                                    "End-of-day reminder",
                                    isOn: Binding(
                                        get: {
                                            model.circles
                                                .first(where: { $0.id == circle.id })?
                                                .endOfDayNotificationsEnabled ?? true
                                        },
                                        set: { enabled in
                                            Task { await model.setEndOfDayNotifications(enabled, for: circle.id) }
                                        }
                                    )
                                )
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        Text("Circle notifications")
                    } footer: {
                        Text("Control activity alerts and the scheduled end-of-day reminder separately for each circle.")
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
    @State private var pendingPhotoResize: PendingPhotoResize?
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
                    pendingPhotoResize = try PendingPhotoResize(data: data)
                } catch {
                    model.message = "Couldn’t prepare that photo: \(error.localizedDescription)"
                }
            }
        }
        .sheet(item: $pendingPhotoResize, onDismiss: { selectedPhoto = nil }) { photo in
            PhotoResizeEditor(
                title: "Resize profile photo",
                photo: photo,
                onCancel: { pendingPhotoResize = nil },
                onUsePhoto: { url in
                    photoURL = url
                    pendingPhotoResize = nil
                }
            )
        }
    }

    @ViewBuilder private var avatarPreview: some View {
        if let photoURL {
            AsyncImage(url: photoURL) { image in image.resizable().scaledToFill() } placeholder: { ProgressView() }
                .frame(width: 96, height: 96)
                .background(AppTheme.surface)
                .clipShape(Circle())
        } else {
            AvatarBadge(member: user, size: 96)
        }
    }
}
