import SwiftUI
import WidgetKit

struct BlessingCircleHomeWidget: Widget {
    let kind = "BlessingCircleHomeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BlessingWidgetProvider()) { entry in
            BlessingWidgetView(entry: entry)
        }
        .configurationDisplayName("manna circle")
        .description("See when it’s time to share or revisit a blessing from your circles.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct BlessingWidgetEntry: TimelineEntry {
    let date: Date
    let content: BlessingWidgetContent
}

struct BlessingWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> BlessingWidgetEntry {
        BlessingWidgetEntry(date: .now, content: .blessing(.placeholder))
    }

    func getSnapshot(in context: Context, completion: @escaping (BlessingWidgetEntry) -> Void) {
        let snapshot = BlessingWidgetSnapshotStore.load()
        let content = context.isPreview
            ? BlessingWidgetContent.blessing(.placeholder)
            : snapshot.content(at: .now, recentlyShownIDs: BlessingWidgetSnapshotStore.recentlyShownIDs())
        completion(BlessingWidgetEntry(date: .now, content: content))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BlessingWidgetEntry>) -> Void) {
        let now = Date.now
        let snapshot = BlessingWidgetSnapshotStore.load()
        let content = snapshot.content(
            at: now,
            recentlyShownIDs: BlessingWidgetSnapshotStore.recentlyShownIDs()
        )
        if case let .blessing(blessing) = content {
            BlessingWidgetSnapshotStore.markShown(blessing.id)
        }
        completion(
            Timeline(
                entries: [BlessingWidgetEntry(date: now, content: content)],
                policy: .after(snapshot.nextRefreshDate(after: now))
            )
        )
    }
}

private struct BlessingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BlessingWidgetEntry

    var body: some View {
        Group {
            switch entry.content {
            case let .share(prompt):
                shareView(prompt)
            case let .blessing(blessing):
                blessingView(blessing)
            case .empty:
                emptyView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .topTrailing) {
            MannaWordmark(width: family == .systemSmall ? 54 : 68)
        }
        .containerBackground(for: .widget) { Color(.systemBackground) }
        .widgetURL(entry.content.deepLink)
    }

    private func shareView(_ prompt: BlessingWidgetPrompt) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "bell.badge.fill")
                .font(.title2)
                .foregroundStyle(MannaWidgetTheme.primary)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            Text("Time to share blessings for \(prompt.circleName)")
                .font(.headline)
                .lineLimit(family == .systemSmall ? 4 : 2)
            Text(timerInterval: entry.date...prompt.endsAt, countsDown: true)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Time to share blessings for \(prompt.circleName)")
        .accessibilityHint("Opens Today in manna circle")
    }

    private func blessingView(_ blessing: BlessingWidgetBlessing) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            blessingHeader(blessing)
                .padding(.trailing, family == .systemSmall ? 54 : 68)

            Text(blessing.transcript)
                .font(.system(family == .systemSmall ? .subheadline : .body, design: .serif))
                .lineLimit(family == .systemSmall ? 4 : 3)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            if let reference = blessing.scriptureReference {
                VStack(alignment: .leading, spacing: 3) {
                    Label(reference, systemImage: "book.closed.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(MannaWidgetTheme.scripture)
                    if family == .systemMedium, let scriptureText = blessing.scriptureText {
                        Text(scriptureText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            } else {
                Text(blessing.submittedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: blessing))
        .accessibilityHint("Opens this blessing")
    }

    @ViewBuilder
    private func blessingHeader(_ blessing: BlessingWidgetBlessing) -> some View {
        if family == .systemSmall {
            VStack(alignment: .leading, spacing: 2) {
                Text(blessing.authorName)
                    .font(.caption.weight(.semibold))
                Text(blessing.circleName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
        } else {
            HStack(spacing: 6) {
                Text(blessing.authorName)
                    .font(.caption.weight(.semibold))
                Text("·")
                    .foregroundStyle(.secondary)
                Text(blessing.circleName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "circle.hexagongrid.fill")
                .font(.title2)
                .foregroundStyle(MannaWidgetTheme.primary)
                .accessibilityHidden(true)
            Spacer()
            Text("Blessings will gather here")
                .font(.headline)
            Text("Open the app to refresh your circles.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func accessibilityLabel(for blessing: BlessingWidgetBlessing) -> String {
        var parts = [
            "Blessing from \(blessing.authorName) in \(blessing.circleName)",
            blessing.transcript,
        ]
        if let reference = blessing.scriptureReference {
            parts.append(reference)
            if let scriptureText = blessing.scriptureText { parts.append(scriptureText) }
        }
        return parts.joined(separator: ". ")
    }
}

private extension BlessingWidgetBlessing {
    static let placeholder = BlessingWidgetBlessing(
        id: UUID(uuidString: "D0000000-0000-0000-0000-000000000001")!,
        circleID: UUID(uuidString: "D0000000-0000-0000-0000-000000000002")!,
        circleName: "Sunday Table",
        authorName: "Ava",
        captureMode: .voice,
        transcript: "A hard conversation that ended with more understanding.",
        submittedAt: .now,
        isFromCurrentCircleDay: true,
        scriptureReference: "Philippians 4:6–7",
        scriptureText: "In everything, by prayer and petition with thanksgiving, let your requests be made known.",
        bibleVersionName: "WEB"
    )
}
