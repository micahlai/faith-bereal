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
        return verses[(verseStart - 1)...(verseEnd - 1)].joined(separator: " ")
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
                        Picker("First verse", selection: $verseStart) {
                            ForEach(1...verseCount, id: \.self) { number in
                                Text("\(number)").tag(number)
                            }
                        }
                        .pickerStyle(.menu)

                        Picker("Last verse", selection: $verseEnd) {
                            ForEach(verseStart...verseCount, id: \.self) { number in
                                Text("\(number)").tag(number)
                            }
                        }
                        .pickerStyle(.menu)
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
                            Text(previewText)
                                .font(.system(.body, design: .serif))
                                .textSelection(.enabled)
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

