import SwiftUI

struct BibleReferencePicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: ScriptureReference?

    @State private var selectedBookID = BibleBook.all[42].id
    @State private var chapter = 3
    @State private var verseStart = 16
    @State private var verseEnd = 16
    @State private var loadedChapter: BibleChapter?
    @State private var isLoading = false
    @State private var loadError: String?

    init(selection: Binding<ScriptureReference?>) {
        _selection = selection
        if let existing = selection.wrappedValue,
           let book = BibleBook.all.first(where: { $0.slug == existing.bookSlug }) {
            _selectedBookID = State(initialValue: book.id)
            _chapter = State(initialValue: existing.chapter)
            _verseStart = State(initialValue: existing.verseStart)
            _verseEnd = State(initialValue: existing.verseEnd)
        }
    }

    private var selectedBook: BibleBook {
        model.bibleBooks.first(where: { $0.id == selectedBookID }) ?? BibleBook.all[42]
    }

    private var verseCount: Int { loadedChapter?.verses.count ?? 0 }

    private var reference: ScriptureReference {
        ScriptureReference(
            bookSlug: selectedBook.slug,
            bookName: selectedBook.name,
            chapter: chapter,
            verseStart: verseStart,
            verseEnd: verseEnd
        )
    }

    private var previewText: String? {
        guard let verses = loadedChapter?.verses,
              verseStart > 0,
              verseEnd <= verses.count else { return nil }
        return BiblePassageFormatter.markedText(
            verses: Array(verses[(verseStart - 1)...(verseEnd - 1)]),
            startingAt: verseStart
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Passage") {
                    Picker("Book", selection: $selectedBookID) {
                        ForEach(model.bibleBooks) { book in
                            Text(book.name).tag(book.id)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("Chapter", selection: $chapter) {
                        ForEach(1...selectedBook.chapterCount, id: \.self) { number in
                            Text("\(number)").tag(number)
                        }
                    }
                    .pickerStyle(.menu)

                    if verseCount > 0 {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Verses")
                                Spacer()
                                Text(verseStart == verseEnd ? "\(verseStart)" : "\(verseStart)–\(verseEnd)")
                                    .font(.subheadline.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(AppTheme.iris)
                            }
                            VerseRangeGrid(
                                verseCount: verseCount,
                                start: $verseStart,
                                end: $verseEnd
                            )
                            VStack(spacing: 8) {
                                Stepper("Start verse: \(verseStart)", value: $verseStart, in: 1...verseEnd)
                                Stepper("End verse: \(verseEnd)", value: $verseEnd, in: verseStart...verseCount)
                            }
                            Text("Drag or tap the grid, or use the start and end controls to select a continuous range.")
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryInk)
                        }
                        .padding(.vertical, 6)
                    }
                }

                Section {
                    if isLoading {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading chapter…")
                                .foregroundStyle(AppTheme.secondaryInk)
                        }
                    } else if let loadError {
                        ContentUnavailableView(
                            "Preview unavailable",
                            systemImage: "wifi.exclamationmark",
                            description: Text(loadError)
                        )
                        Button("Try again") { Task { await loadChapter() } }
                    } else if let previewText {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(reference.displayName)
                                .font(.headline)
                            ExpandablePassageText(
                                text: previewText,
                                title: reference.displayName,
                                translationName: model.selectedBibleTranslation.shortName
                            )
                            Text(model.selectedBibleTranslation.shortName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.secondaryInk)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Preview")
                } footer: {
                    Text("Only the reference is saved. Verse text is loaded in each viewer’s chosen Bible version.")
                }

                Section {
                    Button("Tag \(reference.displayName)") {
                        selection = reference
                        dismiss()
                    }
                    .disabled(previewText == nil)
                }
            }
            .navigationTitle("Tag a Bible verse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if selection != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Remove", role: .destructive) {
                            selection = nil
                            dismiss()
                        }
                    }
                }
            }
            .task(id: "\(selectedBook.slug)-\(chapter)-\(model.selectedBibleTranslation.id)") {
                await loadChapter()
            }
            .onChange(of: selectedBookID) {
                chapter = 1
                verseStart = 1
                verseEnd = 1
                loadedChapter = nil
            }
            .onChange(of: chapter) {
                verseStart = 1
                verseEnd = 1
                loadedChapter = nil
            }
            .onChange(of: verseStart) {
                verseEnd = max(verseStart, verseEnd)
            }
        }
    }

    private func loadChapter() async {
        isLoading = true
        loadError = nil
        do {
            let result = try await model.bibleChapter(book: selectedBook, chapter: chapter)
            guard !Task.isCancelled else { return }
            loadedChapter = result
            let count = max(result.verses.count, 1)
            verseStart = min(max(verseStart, 1), count)
            verseEnd = min(max(verseEnd, verseStart), count)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            loadedChapter = nil
            loadError = "Check your connection, then try again."
        }
        isLoading = false
    }
}

private struct VerseRangeGrid: View {
    let verseCount: Int
    @Binding var start: Int
    @Binding var end: Int
    @State private var cellFrames: [Int: CGRect] = [:]
    @State private var dragAnchor: Int?

    @ScaledMetric(relativeTo: .subheadline) private var cellSize: CGFloat = 44

    private var columns: [GridItem] { [GridItem(.adaptive(minimum: cellSize), spacing: 8)] }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(1...verseCount, id: \.self) { verse in
                Button {
                    start = verse
                    end = verse
                } label: {
                    Text("\(verse)")
                        .font(.subheadline.weight(isSelected(verse) ? .bold : .regular).monospacedDigit())
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(isSelected(verse) ? AppTheme.surface : AppTheme.ink)
                        .background(
                            isSelected(verse) ? AppTheme.iris : AppTheme.surface,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(isSelected(verse) ? AppTheme.iris : AppTheme.secondaryInk, lineWidth: isSelected(verse) ? 3 : 1)
                        }
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: VerseCellFramePreferenceKey.self,
                                    value: [verse: proxy.frame(in: .named("verse-grid"))]
                                )
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Verse \(verse)")
                .accessibilityInputLabels(["Verse \(verse)", "\(verse)"])
                .accessibilityAddTraits(isSelected(verse) ? .isSelected : [])
            }
        }
        .coordinateSpace(name: "verse-grid")
        .onPreferenceChange(VerseCellFramePreferenceKey.self) { cellFrames = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("verse-grid"))
                .onChanged { value in
                    guard let verse = cellFrames.first(where: { $0.value.contains(value.location) })?.key else {
                        return
                    }
                    if dragAnchor == nil { dragAnchor = verse }
                    let anchor = dragAnchor ?? verse
                    start = min(anchor, verse)
                    end = max(anchor, verse)
                }
                .onEnded { _ in dragAnchor = nil }
        )
    }

    private func isSelected(_ verse: Int) -> Bool {
        (start...end).contains(verse)
    }
}

private struct VerseCellFramePreferenceKey: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
