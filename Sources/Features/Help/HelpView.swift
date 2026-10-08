import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("A little guidance, whenever you need it.")
                        .font(.system(.title, design: .serif, weight: .regular))
                    ForEach(HelpTopic.allCases) { topic in
                        NavigationLink {
                            HelpTopicView(topic: topic)
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: topic.icon)
                                    .font(.title2)
                                    .frame(width: 48, height: 48)
                                    .background(AppTheme.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(topic.title).font(.headline)
                                    Text(topic.summary).font(.subheadline).foregroundStyle(AppTheme.secondaryInk)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").accessibilityHidden(true)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .blessingCard()
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("help-topic-\(topic.rawValue)")
                    }
                }
                .frame(maxWidth: 620)
                .padding(AppTheme.pagePadding)
                .frame(maxWidth: .infinity)
            }
            .background(AppTheme.canvas)
            .navigationTitle("Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

private struct HelpTopicView: View {
    @State private var topic: HelpTopic

    init(topic: HelpTopic) { _topic = State(initialValue: topic) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Label(topic.title, systemImage: topic.icon)
                    .font(.system(.title, design: .serif, weight: .regular))
                    .foregroundStyle(AppTheme.primary)
                Text(topic.summary).font(.title3).foregroundStyle(AppTheme.secondaryInk)
                ForEach(Array(topic.steps.enumerated()), id: \.offset) { index, step in
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 12) {
                            Image(systemName: step.icon)
                                .font(.title2)
                                .frame(width: 48, height: 48)
                                .background(AppTheme.primary.opacity(0.10), in: Circle())
                                .foregroundStyle(AppTheme.primary)
                                .accessibilityHidden(true)
                            Text("\(index + 1). \(step.title)").font(.headline)
                        }
                        Text(step.body).font(.body).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .blessingCard()
                }
            }
            .frame(maxWidth: 620)
            .padding(AppTheme.pagePadding)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.canvas)
        .navigationTitle(topic.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(HelpTopic.allCases) { nextTopic in
                        Button(nextTopic.title) { topic = nextTopic }
                    }
                } label: {
                    Label("Topics", systemImage: "list.bullet")
                        .frame(minHeight: 44)
                }
                .accessibilityLabel("Jump to help topic")
            }
        }
    }
}
