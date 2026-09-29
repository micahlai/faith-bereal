import SwiftUI

struct CircleView: View {
    @Environment(AppModel.self) private var model
    @State private var joinCode = ""
    @State private var newCircleName = ""
    @State private var showingJoin = false
    @State private var showingCreate = false

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
                    if member.id == model.circle?.members.first?.id {
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
