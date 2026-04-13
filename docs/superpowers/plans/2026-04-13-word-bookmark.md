# Word Bookmark Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users bookmark unfamiliar words (with their sentence context) from articles and view them in a date-grouped list.

**Architecture:** New `BookmarkedWord` model persisted as JSON in Documents directory. `BookmarkStore` (protocol-backed `ObservableObject`) manages CRUD and file I/O. The edit menu in `SelectableAttributedTextView` gains a "收藏" action that extracts the enclosing sentence and calls up through the existing callback chain to `ArticleReaderView`, which writes to the store. A new `BookmarkListView` is pushed from the TodayView toolbar.

**Tech Stack:** Swift, SwiftUI, UIKit (edit menu), Foundation (JSONEncoder/Decoder, FileManager)

---

### Task 1: BookmarkedWord Model

**Files:**
- Create: `VocabReader/Models/BookmarkedWord.swift`
- Test: `VocabReaderTests/BookmarkedWordTests.swift`

- [ ] **Step 1: Write the failing test**

Create `VocabReaderTests/BookmarkedWordTests.swift`:

```swift
import XCTest
@testable import VocabReader

final class BookmarkedWordTests: XCTestCase {
    func testRoundTripCodable() throws {
        let word = BookmarkedWord(
            id: UUID(),
            spelling: "ephemeral",
            sentence: "The ephemeral beauty of cherry blossoms fades quickly.",
            bookmarkedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let data = try JSONEncoder().encode(word)
        let decoded = try JSONDecoder().decode(BookmarkedWord.self, from: data)

        XCTAssertEqual(decoded.id, word.id)
        XCTAssertEqual(decoded.spelling, word.spelling)
        XCTAssertEqual(decoded.sentence, word.sentence)
        XCTAssertEqual(decoded.bookmarkedAt, word.bookmarkedAt)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project VocabReader.xcodeproj -scheme VocabReader -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:VocabReaderTests/BookmarkedWordTests 2>&1 | tail -20`
Expected: FAIL — `BookmarkedWord` not defined.

- [ ] **Step 3: Write minimal implementation**

Create `VocabReader/Models/BookmarkedWord.swift`:

```swift
import Foundation

struct BookmarkedWord: Identifiable, Codable, Equatable {
    let id: UUID
    let spelling: String
    let sentence: String
    let bookmarkedAt: Date
}
```

Add both new files to the Xcode project's appropriate targets (BookmarkedWord.swift to VocabReader target, BookmarkedWordTests.swift to VocabReaderTests target).

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project VocabReader.xcodeproj -scheme VocabReader -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:VocabReaderTests/BookmarkedWordTests 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add VocabReader/Models/BookmarkedWord.swift VocabReaderTests/BookmarkedWordTests.swift VocabReader.xcodeproj
git commit -m "feat: add BookmarkedWord model with Codable support"
```

---

### Task 2: BookmarkStore with JSON Persistence

**Files:**
- Create: `VocabReader/Services/BookmarkStore.swift`
- Test: `VocabReaderTests/BookmarkStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `VocabReaderTests/BookmarkStoreTests.swift`:

```swift
import XCTest
@testable import VocabReader

final class BookmarkStoreTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookmarkStoreTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    private func makeStore() -> BookmarkStore {
        BookmarkStore(directory: tempDirectory)
    }

    func testAddBookmarkAppendsToList() {
        let store = makeStore()
        XCTAssertTrue(store.bookmarks.isEmpty)

        store.add(spelling: "ephemeral", sentence: "The ephemeral beauty fades quickly.")

        XCTAssertEqual(store.bookmarks.count, 1)
        XCTAssertEqual(store.bookmarks.first?.spelling, "ephemeral")
        XCTAssertEqual(store.bookmarks.first?.sentence, "The ephemeral beauty fades quickly.")
    }

    func testRemoveBookmarkDeletesById() {
        let store = makeStore()
        store.add(spelling: "ephemeral", sentence: "Sentence one.")
        store.add(spelling: "ubiquitous", sentence: "Sentence two.")
        let idToRemove = store.bookmarks.first!.id

        store.remove(id: idToRemove)

        XCTAssertEqual(store.bookmarks.count, 1)
        XCTAssertEqual(store.bookmarks.first?.spelling, "ubiquitous")
    }

    func testPersistenceRoundTrip() {
        let store1 = makeStore()
        store1.add(spelling: "ephemeral", sentence: "Sentence one.")
        store1.add(spelling: "ubiquitous", sentence: "Sentence two.")

        let store2 = makeStore()
        XCTAssertEqual(store2.bookmarks.count, 2)
        XCTAssertEqual(store2.bookmarks[0].spelling, "ephemeral")
        XCTAssertEqual(store2.bookmarks[1].spelling, "ubiquitous")
    }

    func testRemovePersistsAfterReload() {
        let store1 = makeStore()
        store1.add(spelling: "ephemeral", sentence: "Sentence one.")
        store1.add(spelling: "ubiquitous", sentence: "Sentence two.")
        store1.remove(id: store1.bookmarks.first!.id)

        let store2 = makeStore()
        XCTAssertEqual(store2.bookmarks.count, 1)
        XCTAssertEqual(store2.bookmarks.first?.spelling, "ubiquitous")
    }

    func testEmptyFileLoadsGracefully() {
        let store = makeStore()
        XCTAssertTrue(store.bookmarks.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project VocabReader.xcodeproj -scheme VocabReader -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:VocabReaderTests/BookmarkStoreTests 2>&1 | tail -20`
Expected: FAIL — `BookmarkStore` not defined.

- [ ] **Step 3: Write minimal implementation**

Create `VocabReader/Services/BookmarkStore.swift`:

```swift
import Foundation

protocol BookmarkStoreProtocol: ObservableObject {
    var bookmarks: [BookmarkedWord] { get }
    func add(spelling: String, sentence: String)
    func remove(id: UUID)
}

final class BookmarkStore: BookmarkStoreProtocol, ObservableObject {
    @Published private(set) var bookmarks: [BookmarkedWord] = []

    private let fileURL: URL

    static let shared = BookmarkStore()

    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.fileURL = dir.appendingPathComponent("bookmarks.json")
        load()
    }

    func add(spelling: String, sentence: String) {
        let word = BookmarkedWord(
            id: UUID(),
            spelling: spelling,
            sentence: sentence,
            bookmarkedAt: Date()
        )
        bookmarks.append(word)
        save()
    }

    func remove(id: UUID) {
        bookmarks.removeAll { $0.id == id }
        save()
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(bookmarks)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // File write failed — bookmarks remain in memory
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        bookmarks = (try? JSONDecoder().decode([BookmarkedWord].self, from: data)) ?? []
    }
}
```

Add both new files to the Xcode project.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project VocabReader.xcodeproj -scheme VocabReader -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:VocabReaderTests/BookmarkStoreTests 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add VocabReader/Services/BookmarkStore.swift VocabReaderTests/BookmarkStoreTests.swift VocabReader.xcodeproj
git commit -m "feat: add BookmarkStore with JSON file persistence"
```

---

### Task 3: Sentence Extraction Helper

**Files:**
- Create: `VocabReader/Services/SentenceExtractor.swift`
- Test: `VocabReaderTests/SentenceExtractorTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `VocabReaderTests/SentenceExtractorTests.swift`:

```swift
import XCTest
@testable import VocabReader

final class SentenceExtractorTests: XCTestCase {
    func testExtractsSentenceContainingWord() {
        let paragraph = "The sun rose slowly. The ephemeral beauty of cherry blossoms fades quickly. Birds sang in the trees."
        let result = SentenceExtractor.sentence(containing: "ephemeral", in: paragraph)
        XCTAssertEqual(result, "The ephemeral beauty of cherry blossoms fades quickly.")
    }

    func testCaseInsensitiveMatch() {
        let paragraph = "She felt Ubiquitous pressure from all sides. It was overwhelming."
        let result = SentenceExtractor.sentence(containing: "ubiquitous", in: paragraph)
        XCTAssertEqual(result, "She felt Ubiquitous pressure from all sides.")
    }

    func testReturnsFirstMatchWhenMultipleSentences() {
        let paragraph = "Ephemeral joys are common. Another ephemeral moment passed."
        let result = SentenceExtractor.sentence(containing: "ephemeral", in: paragraph)
        XCTAssertEqual(result, "Ephemeral joys are common.")
    }

    func testReturnsFullParagraphWhenNoSentenceBoundary() {
        let paragraph = "A single phrase with ephemeral inside"
        let result = SentenceExtractor.sentence(containing: "ephemeral", in: paragraph)
        XCTAssertEqual(result, "A single phrase with ephemeral inside")
    }

    func testReturnsFullTextWhenWordNotFound() {
        let paragraph = "No matching word here."
        let result = SentenceExtractor.sentence(containing: "ephemeral", in: paragraph)
        XCTAssertEqual(result, "No matching word here.")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project VocabReader.xcodeproj -scheme VocabReader -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:VocabReaderTests/SentenceExtractorTests 2>&1 | tail -20`
Expected: FAIL — `SentenceExtractor` not defined.

- [ ] **Step 3: Write minimal implementation**

Create `VocabReader/Services/SentenceExtractor.swift`:

```swift
import Foundation

enum SentenceExtractor {
    static func sentence(containing word: String, in text: String) -> String {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        var match: String?

        nsText.enumerateSubstrings(in: fullRange, options: .bySentences) { substring, _, _, stop in
            guard let substring else { return }
            if substring.localizedCaseInsensitiveContains(word) {
                match = substring.trimmingCharacters(in: .whitespacesAndNewlines)
                stop.pointee = true
            }
        }

        return match ?? text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

Add both new files to the Xcode project.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project VocabReader.xcodeproj -scheme VocabReader -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:VocabReaderTests/SentenceExtractorTests 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add VocabReader/Services/SentenceExtractor.swift VocabReaderTests/SentenceExtractorTests.swift VocabReader.xcodeproj
git commit -m "feat: add SentenceExtractor for finding sentence containing a word"
```

---

### Task 4: Add "收藏" Action to Edit Menu in ArticleReaderView

**Files:**
- Modify: `VocabReader/Views/ArticleReaderView.swift`

This task modifies the callback chain from `SelectableAttributedTextView` up to `ArticleReaderView`.

- [ ] **Step 1: Add `onBookmarkSelection` callback to `SelectableAttributedTextView`**

In `ArticleReaderView.swift`, add a new callback parameter to `SelectableAttributedTextView`:

```swift
private struct SelectableAttributedTextView: UIViewRepresentable {
    let attributedText: NSAttributedString
    let onOpenURL: (URL) -> Void
    let onTranslateSelection: (String) -> Void
    let onBookmarkSelection: (String) -> Void
```

Update `makeCoordinator()` to pass it:

```swift
    func makeCoordinator() -> Coordinator {
        Coordinator(
            onOpenURL: onOpenURL,
            onTranslateSelection: onTranslateSelection,
            onBookmarkSelection: onBookmarkSelection
        )
    }
```

Update `updateUIView` to sync it:

```swift
    func updateUIView(_ uiView: UITextView, context: Context) {
        let styledText = makeStyledAttributedText()
        if uiView.attributedText != styledText {
            uiView.attributedText = styledText
        }
        context.coordinator.onOpenURL = onOpenURL
        context.coordinator.onTranslateSelection = onTranslateSelection
        context.coordinator.onBookmarkSelection = onBookmarkSelection
    }
```

- [ ] **Step 2: Add callback and "收藏" action to Coordinator**

Add `onBookmarkSelection` to the Coordinator class:

```swift
    final class Coordinator: NSObject, UITextViewDelegate {
        var onOpenURL: (URL) -> Void
        var onTranslateSelection: (String) -> Void
        var onBookmarkSelection: (String) -> Void

        init(
            onOpenURL: @escaping (URL) -> Void,
            onTranslateSelection: @escaping (String) -> Void,
            onBookmarkSelection: @escaping (String) -> Void
        ) {
            self.onOpenURL = onOpenURL
            self.onTranslateSelection = onTranslateSelection
            self.onBookmarkSelection = onBookmarkSelection
        }
```

Update `editMenuForTextIn` to add the "收藏" action:

```swift
        func textView(
            _ textView: UITextView,
            editMenuForTextIn range: NSRange,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            let selectedText = (textView.text as NSString).substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)

            guard !selectedText.isEmpty else {
                return UIMenu(children: suggestedActions)
            }

            let translateAction = UIAction(title: "翻译") { [onTranslateSelection] _ in
                onTranslateSelection(selectedText)
            }

            let fullText = textView.text ?? ""
            let bookmarkAction = UIAction(title: "收藏", image: UIImage(systemName: "star")) { [onBookmarkSelection] _ in
                let sentence = SentenceExtractor.sentence(containing: selectedText, in: fullText)
                onBookmarkSelection(selectedText + "\n" + sentence)
            }

            return UIMenu(children: suggestedActions + [translateAction, bookmarkAction])
        }
```

Note: We pack `word + "\n" + sentence` into a single string to keep the callback signature simple, then split it at the call site.

- [ ] **Step 3: Thread the callback through ArticleParagraphSection**

Add `onBookmarkSelection` to `ArticleParagraphSection`:

```swift
private struct ArticleParagraphSection: View {
    let paragraph: ArticleParagraph
    let targetWords: [VocabWord]
    let formatter: ArticleContentFormatter
    let isHighlighted: Bool
    let onWordTap: (String) -> Void
    let onBookmarkSelection: (String) -> Void
    let onTapParagraph: () -> Void
```

Update its `init`:

```swift
    init(
        paragraph: ArticleParagraph,
        targetWords: [VocabWord],
        formatter: ArticleContentFormatter,
        translator: ArticleParagraphTranslatorProtocol,
        isHighlighted: Bool = false,
        onWordTap: @escaping (String) -> Void,
        onBookmarkSelection: @escaping (String) -> Void,
        onTapParagraph: @escaping () -> Void = {}
    ) {
```

(Store `onBookmarkSelection` in the existing property assignment block.)

Pass it to `SelectableAttributedTextView` in the body:

```swift
            SelectableAttributedTextView(
                attributedText: NSAttributedString(
                    formatter.formatParagraph(
                        content: paragraph.content,
                        targetWords: targetWords,
                        paragraphIndex: paragraph.index,
                        actionTitle: inlineActionTitle
                    )
                ),
                onOpenURL: { url in
                    if url.scheme == "paragraph", url.host(percentEncoded: false) == "\(paragraph.index)" {
                        Task {
                            await viewModel.didTapTranslateButton()
                        }
                        return
                    }

                    if url.scheme == "word", let spelling = url.host(percentEncoded: false) {
                        onWordTap(spelling)
                    }
                },
                onTranslateSelection: { selectedText in
                    onWordTap(selectedText)
                },
                onBookmarkSelection: { packed in
                    onBookmarkSelection(packed)
                }
            )
```

- [ ] **Step 4: Wire up BookmarkStore in ArticleReaderView**

Add a `@StateObject` for the store and pass the bookmark callback in the ForEach:

```swift
struct ArticleReaderView: View {
    let article: Article
    let translator: WordTranslatorServiceProtocol
    let paragraphTranslator: ArticleParagraphTranslatorProtocol

    @State private var translationText: String = ""
    @State private var showTranslation = false
    @StateObject private var audioPlayer: ArticleAudioPlayerViewModel
    @StateObject private var bookmarkStore = BookmarkStore.shared
    private let formatter = ArticleContentFormatter()
    private let extractor = ArticleParagraphExtractor()
    private let paragraphs: [ArticleParagraph]
```

In the `ForEach`, pass `onBookmarkSelection`:

```swift
                        ForEach(paragraphs) { paragraph in
                            ArticleParagraphSection(
                                paragraph: paragraph,
                                targetWords: article.targetWords,
                                formatter: formatter,
                                translator: paragraphTranslator,
                                isHighlighted: audioPlayer.currentParagraphIndex == paragraph.index,
                                onWordTap: { spelling in
                                    translationText = spelling
                                    showTranslation = true
                                },
                                onBookmarkSelection: { packed in
                                    let parts = packed.split(separator: "\n", maxSplits: 1)
                                    let word = String(parts[0])
                                    let sentence = parts.count > 1 ? String(parts[1]) : word
                                    bookmarkStore.add(spelling: word, sentence: sentence)
                                },
                                onTapParagraph: {
                                    audioPlayer.playFromParagraph(paragraph.index)
                                }
                            )
                            .id(paragraph.index)
                        }
```

- [ ] **Step 5: Build and verify**

Run: `xcodebuild build -project VocabReader.xcodeproj -scheme VocabReader -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add VocabReader/Views/ArticleReaderView.swift VocabReader.xcodeproj
git commit -m "feat: add 收藏 action to text selection edit menu"
```

---

### Task 5: BookmarkListView

**Files:**
- Create: `VocabReader/Views/BookmarkListView.swift`

- [ ] **Step 1: Create BookmarkListView**

Create `VocabReader/Views/BookmarkListView.swift`:

```swift
import SwiftUI

struct BookmarkListView: View {
    @ObservedObject var store: BookmarkStore

    @State private var expandedWordID: UUID?

    var body: some View {
        Group {
            if store.bookmarks.isEmpty {
                ContentUnavailableView(
                    "暂无收藏",
                    systemImage: "star",
                    description: Text("在阅读文章时长按选中单词，点击"收藏"即可添加")
                )
            } else {
                List {
                    ForEach(groupedByDate, id: \.date) { group in
                        Section {
                            ForEach(group.words) { word in
                                BookmarkRow(
                                    word: word,
                                    isExpanded: expandedWordID == word.id
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation {
                                        expandedWordID = expandedWordID == word.id ? nil : word.id
                                    }
                                }
                            }
                            .onDelete { offsets in
                                let wordsToDelete = offsets.map { group.words[$0] }
                                for word in wordsToDelete {
                                    store.remove(id: word.id)
                                }
                            }
                        } header: {
                            Text(group.dateLabel)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("收藏单词")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var groupedByDate: [DateGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: store.bookmarks) { word in
            calendar.startOfDay(for: word.bookmarkedAt)
        }
        return grouped
            .map { DateGroup(date: $0.key, words: $0.value) }
            .sorted { $0.date > $1.date }
    }
}

private struct DateGroup {
    let date: Date
    let words: [BookmarkedWord]

    var dateLabel: String {
        date.formatted(.dateTime.year().month().day())
    }
}

private struct BookmarkRow: View {
    let word: BookmarkedWord
    let isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(word.spelling)
                .font(.system(.body, design: .serif))
                .fontWeight(.medium)

            if isExpanded {
                Text(word.sentence)
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(.secondary)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
    }
}
```

Add to the Xcode project's VocabReader target.

- [ ] **Step 2: Build and verify**

Run: `xcodebuild build -project VocabReader.xcodeproj -scheme VocabReader -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add VocabReader/Views/BookmarkListView.swift VocabReader.xcodeproj
git commit -m "feat: add BookmarkListView with date-grouped display"
```

---

### Task 6: Add Navigation Entry Point in TodayView

**Files:**
- Modify: `VocabReader/Views/TodayView.swift`

- [ ] **Step 1: Add star button and navigation destination**

In `TodayView`, add state and navigation for bookmarks:

```swift
struct TodayView: View {
    @StateObject private var viewModel = TodayViewModel()
    @StateObject private var bookmarkStore = BookmarkStore.shared
    @State private var showSettings = false
    @State private var showBookmarks = false
    @State private var selectedArticle: Article?
    @State private var settingsSnapshot = SettingsStore.shared.articleGenerationSettings
```

In the toolbar, add a leading star button:

```swift
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        showBookmarks = true
                    } label: {
                        Image(systemName: "star")
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    // ... existing buttons unchanged
                }
            }
```

Add a `navigationDestination` for bookmarks:

```swift
            .navigationDestination(isPresented: $showBookmarks) {
                BookmarkListView(store: bookmarkStore)
            }
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild build -project VocabReader.xcodeproj -scheme VocabReader -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add VocabReader/Views/TodayView.swift
git commit -m "feat: add star toolbar button to navigate to bookmark list"
```

---

### Task 7: Run All Tests and Final Verification

- [ ] **Step 1: Run all tests**

Run: `xcodebuild test -project VocabReader.xcodeproj -scheme VocabReader -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -30`
Expected: All tests pass, including new `BookmarkedWordTests`, `BookmarkStoreTests`, `SentenceExtractorTests`.

- [ ] **Step 2: Build and launch simulator for manual verification**

Run: `xcodebuild build -project VocabReader.xcodeproj -scheme VocabReader -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10`

Manual checks:
1. TodayView shows a star icon in the top-left toolbar
2. Tapping the star navigates to an empty bookmark list with placeholder text
3. In an article, long-press to select a word — edit menu shows "翻译" and "收藏"
4. Tapping "收藏" adds the word to the bookmark list
5. Bookmark list groups words by date
6. Tapping a word row expands to show the sentence
7. Swiping left on a row deletes the bookmark

- [ ] **Step 3: Final commit if any fixes needed**

```bash
git add -A
git commit -m "fix: address issues found during manual verification"
```
