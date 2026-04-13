# Word Bookmark Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users bookmark unfamiliar words (with their containing sentence) from articles, persisted as JSON, browsable in a date-grouped list.

**Architecture:** New `BookmarkedWord` model + `BookmarkStore` service for JSON persistence + `BookmarkListView` for display. The edit menu in `ArticleReaderView` gets a "收藏" action that extracts the sentence and delegates to the store. TodayView toolbar gains a star icon entry point.

**Tech Stack:** Swift, SwiftUI, UIKit (UITextView edit menu), Foundation (JSONEncoder/FileManager)

---

### Task 1: BookmarkedWord Model

**Files:**
- Create: `VocabReader/Models/BookmarkedWord.swift`
- Test: `VocabReaderTests/BookmarkStoreTests.swift`

- [ ] **Step 1: Create the model file**

```swift
import Foundation

struct BookmarkedWord: Identifiable, Codable, Equatable {
    let id: UUID
    let spelling: String
    let sentence: String
    let bookmarkedAt: Date

    init(id: UUID = UUID(), spelling: String, sentence: String, bookmarkedAt: Date = Date()) {
        self.id = id
        self.spelling = spelling
        self.sentence = sentence
        self.bookmarkedAt = bookmarkedAt
    }
}
```

- [ ] **Step 2: Add file to Xcode project**

The project uses automatic file discovery — just ensure the file is in the `VocabReader/Models/` directory. Build to confirm:

```bash
xcodebuild -scheme VocabReader -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add VocabReader/Models/BookmarkedWord.swift
git commit -m "feat: add BookmarkedWord model"
```

---

### Task 2: BookmarkStore with Protocol and JSON Persistence

**Files:**
- Create: `VocabReader/Services/BookmarkStore.swift`
- Create: `VocabReaderTests/BookmarkStoreTests.swift`

- [ ] **Step 1: Write failing tests**

Create `VocabReaderTests/BookmarkStoreTests.swift`:

```swift
import XCTest
@testable import VocabReader

final class BookmarkStoreTests: XCTestCase {
    private var tempURL: URL!
    private var store: BookmarkStore!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bookmark-tests-\(UUID().uuidString).json")
        store = BookmarkStore(fileURL: tempURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }

    func testAddBookmarkAppendsToList() {
        store.add(spelling: "ephemeral", sentence: "The ephemeral beauty of cherry blossoms.")

        XCTAssertEqual(store.bookmarks.count, 1)
        XCTAssertEqual(store.bookmarks[0].spelling, "ephemeral")
        XCTAssertEqual(store.bookmarks[0].sentence, "The ephemeral beauty of cherry blossoms.")
    }

    func testRemoveBookmarkDeletesById() {
        store.add(spelling: "ephemeral", sentence: "Sentence A.")
        store.add(spelling: "transient", sentence: "Sentence B.")
        let idToRemove = store.bookmarks[0].id

        store.remove(id: idToRemove)

        XCTAssertEqual(store.bookmarks.count, 1)
        XCTAssertEqual(store.bookmarks[0].spelling, "transient")
    }

    func testPersistenceRoundTrip() {
        store.add(spelling: "ephemeral", sentence: "The ephemeral beauty.")

        let reloaded = BookmarkStore(fileURL: tempURL)

        XCTAssertEqual(reloaded.bookmarks.count, 1)
        XCTAssertEqual(reloaded.bookmarks[0].spelling, "ephemeral")
        XCTAssertEqual(reloaded.bookmarks[0].sentence, "The ephemeral beauty.")
    }

    func testLoadFromMissingFileStartsEmpty() {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent-\(UUID().uuidString).json")
        let emptyStore = BookmarkStore(fileURL: missingURL)

        XCTAssertTrue(emptyStore.bookmarks.isEmpty)
    }

    func testContainsReturnsTrueForExistingSpelling() {
        store.add(spelling: "ephemeral", sentence: "Some sentence.")

        XCTAssertTrue(store.contains(spelling: "ephemeral"))
        XCTAssertFalse(store.contains(spelling: "transient"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -scheme VocabReader -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing VocabReaderTests/BookmarkStoreTests 2>&1 | tail -10
```

Expected: FAIL — `BookmarkStore` does not exist yet.

- [ ] **Step 3: Implement BookmarkStore**

Create `VocabReader/Services/BookmarkStore.swift`:

```swift
import Foundation

protocol BookmarkStoreProtocol: AnyObject {
    var bookmarks: [BookmarkedWord] { get }
    func add(spelling: String, sentence: String)
    func remove(id: UUID)
    func contains(spelling: String) -> Bool
}

final class BookmarkStore: ObservableObject, BookmarkStoreProtocol {
    @Published private(set) var bookmarks: [BookmarkedWord] = []

    private let fileURL: URL

    static let shared = BookmarkStore()

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        load()
    }

    func add(spelling: String, sentence: String) {
        let bookmark = BookmarkedWord(spelling: spelling, sentence: sentence)
        bookmarks.append(bookmark)
        save()
    }

    func remove(id: UUID) {
        bookmarks.removeAll { $0.id == id }
        save()
    }

    func contains(spelling: String) -> Bool {
        bookmarks.contains { $0.spelling.lowercased() == spelling.lowercased() }
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
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([BookmarkedWord].self, from: data) else {
            return
        }
        bookmarks = decoded
    }

    private static func defaultFileURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("bookmarks.json")
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -scheme VocabReader -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing VocabReaderTests/BookmarkStoreTests 2>&1 | tail -10
```

Expected: All 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add VocabReader/Services/BookmarkStore.swift VocabReaderTests/BookmarkStoreTests.swift
git commit -m "feat: add BookmarkStore with JSON persistence and tests"
```

---

### Task 3: Add "收藏" Action to Edit Menu

**Files:**
- Modify: `VocabReader/Views/ArticleReaderView.swift`

This task threads a new `onBookmarkSelection` callback through the view hierarchy and adds a "收藏" button to the UITextView edit menu. It also extracts the sentence containing the selected word.

- [ ] **Step 1: Add onBookmarkSelection to SelectableAttributedTextView**

In `ArticleReaderView.swift`, modify `SelectableAttributedTextView` to accept a new callback and the full paragraph text:

Add two new properties to `SelectableAttributedTextView` (after the existing `onTranslateSelection`):

```swift
let paragraphText: String
let onBookmarkSelection: (String, String) -> Void  // (word, sentence)
```

Update `makeCoordinator()` to pass the new fields:

```swift
func makeCoordinator() -> Coordinator {
    Coordinator(
        onOpenURL: onOpenURL,
        onTranslateSelection: onTranslateSelection,
        paragraphText: paragraphText,
        onBookmarkSelection: onBookmarkSelection
    )
}
```

Update `updateUIView` to sync the new fields:

```swift
func updateUIView(_ uiView: UITextView, context: Context) {
    let styledText = makeStyledAttributedText()
    if uiView.attributedText != styledText {
        uiView.attributedText = styledText
    }
    context.coordinator.onOpenURL = onOpenURL
    context.coordinator.onTranslateSelection = onTranslateSelection
    context.coordinator.paragraphText = paragraphText
    context.coordinator.onBookmarkSelection = onBookmarkSelection
}
```

- [ ] **Step 2: Update Coordinator with sentence extraction and bookmark action**

Add new properties and the sentence extraction helper to `Coordinator`:

```swift
var paragraphText: String
var onBookmarkSelection: (String, String) -> Void

init(
    onOpenURL: @escaping (URL) -> Void,
    onTranslateSelection: @escaping (String) -> Void,
    paragraphText: String,
    onBookmarkSelection: @escaping (String, String) -> Void
) {
    self.onOpenURL = onOpenURL
    self.onTranslateSelection = onTranslateSelection
    self.paragraphText = paragraphText
    self.onBookmarkSelection = onBookmarkSelection
}
```

Add sentence extraction method to `Coordinator`:

```swift
private func extractSentence(containing word: String, from text: String) -> String {
    var result = text
    let nsText = text as NSString
    let fullRange = NSRange(location: 0, length: nsText.length)
    nsText.enumerateSubstrings(in: fullRange, options: .bySentences) { sentence, _, _, stop in
        guard let sentence else { return }
        if sentence.localizedCaseInsensitiveContains(word) {
            result = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            stop.pointee = true
        }
    }
    return result
}
```

Update `editMenuForTextIn` to add the bookmark action:

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

    let bookmarkAction = UIAction(title: "收藏", image: UIImage(systemName: "star")) { [weak self] _ in
        guard let self else { return }
        let sentence = extractSentence(containing: selectedText, from: paragraphText)
        onBookmarkSelection(selectedText, sentence)
    }

    return UIMenu(children: suggestedActions + [translateAction, bookmarkAction])
}
```

- [ ] **Step 3: Thread callback through ArticleParagraphSection**

Add `onBookmarkWord` parameter to `ArticleParagraphSection`:

```swift
let onBookmarkWord: (String, String) -> Void
```

Update the `init` to accept it:

```swift
init(
    paragraph: ArticleParagraph,
    targetWords: [VocabWord],
    formatter: ArticleContentFormatter,
    translator: ArticleParagraphTranslatorProtocol,
    isHighlighted: Bool = false,
    onWordTap: @escaping (String) -> Void,
    onTapParagraph: @escaping () -> Void = {},
    onBookmarkWord: @escaping (String, String) -> Void = { _, _ in }
) {
    // ... existing assignments ...
    self.onBookmarkWord = onBookmarkWord
    // ...
}
```

Update the `SelectableAttributedTextView` call site in the `body` to pass the new parameters:

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
    paragraphText: paragraph.content,
    onBookmarkSelection: onBookmarkWord
)
```

- [ ] **Step 4: Thread callback through ArticleReaderView**

Add `BookmarkStore` to `ArticleReaderView`. Add a property:

```swift
@ObservedObject private var bookmarkStore = BookmarkStore.shared
```

Update the `ForEach` in `body` to pass the bookmark callback to `ArticleParagraphSection`:

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
        onTapParagraph: {
            audioPlayer.playFromParagraph(paragraph.index)
        },
        onBookmarkWord: { word, sentence in
            bookmarkStore.add(spelling: word, sentence: sentence)
        }
    )
    .id(paragraph.index)
}
```

- [ ] **Step 5: Build to verify compilation**

```bash
xcodebuild -scheme VocabReader -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add VocabReader/Views/ArticleReaderView.swift
git commit -m "feat: add bookmark action to text selection edit menu"
```

---

### Task 4: BookmarkListView

**Files:**
- Create: `VocabReader/Views/BookmarkListView.swift`

- [ ] **Step 1: Create BookmarkListView**

```swift
import SwiftUI

struct BookmarkListView: View {
    @ObservedObject var store: BookmarkStore

    @State private var expandedID: UUID?

    var body: some View {
        Group {
            if store.bookmarks.isEmpty {
                ContentUnavailableView(
                    "暂无收藏",
                    systemImage: "star",
                    description: Text("阅读文章时长按选词，点击"收藏"即可添加")
                )
            } else {
                List {
                    ForEach(groupedByDate, id: \.date) { group in
                        Section {
                            ForEach(group.words) { word in
                                BookmarkRow(
                                    word: word,
                                    isExpanded: expandedID == word.id,
                                    onTap: {
                                        withAnimation {
                                            expandedID = expandedID == word.id ? nil : word.id
                                        }
                                    }
                                )
                            }
                            .onDelete { offsets in
                                deleteWords(in: group, at: offsets)
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

    private var groupedByDate: [BookmarkGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: store.bookmarks) { word in
            calendar.startOfDay(for: word.bookmarkedAt)
        }
        return grouped
            .map { BookmarkGroup(date: $0.key, words: $0.value) }
            .sorted { $0.date > $1.date }
    }

    private func deleteWords(in group: BookmarkGroup, at offsets: IndexSet) {
        for index in offsets {
            store.remove(id: group.words[index].id)
        }
    }
}

private struct BookmarkGroup {
    let date: Date
    let words: [BookmarkedWord]

    var dateLabel: String {
        date.formatted(.dateTime.year().month().day())
    }
}

private struct BookmarkRow: View {
    let word: BookmarkedWord
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(word.spelling)
                    .font(.body.bold())
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
            }

            if isExpanded {
                Text(word.sentence)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}
```

- [ ] **Step 2: Build to verify compilation**

```bash
xcodebuild -scheme VocabReader -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add VocabReader/Views/BookmarkListView.swift
git commit -m "feat: add BookmarkListView with date-grouped display"
```

---

### Task 5: Wire Up Navigation from TodayView

**Files:**
- Modify: `VocabReader/Views/TodayView.swift`

- [ ] **Step 1: Add star icon and navigation to TodayView**

In `TodayView`, add a state variable for navigation:

```swift
@State private var showBookmarks = false
```

Add a leading toolbar button and a `navigationDestination` modifier. In the `toolbar` block, add a new `ToolbarItemGroup` for the leading side:

```swift
ToolbarItemGroup(placement: .topBarLeading) {
    Button {
        showBookmarks = true
    } label: {
        Image(systemName: "star")
    }
}
```

Add a `navigationDestination` modifier after the existing `.navigationDestination(item: $selectedArticle)`:

```swift
.navigationDestination(isPresented: $showBookmarks) {
    BookmarkListView(store: BookmarkStore.shared)
}
```

- [ ] **Step 2: Build and run to verify**

```bash
xcodebuild -scheme VocabReader -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Run all tests to verify nothing is broken**

```bash
xcodebuild test -scheme VocabReader -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -15
```

Expected: All tests PASS.

- [ ] **Step 4: Commit**

```bash
git add VocabReader/Views/TodayView.swift
git commit -m "feat: add bookmark list entry in TodayView toolbar"
```
