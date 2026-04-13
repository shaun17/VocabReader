# Word Bookmark Feature Design

## Overview

Add a word bookmarking feature to VocabReader that lets users collect unfamiliar words encountered while reading articles. Each bookmark captures the word and the sentence it appeared in. Bookmarks are persisted locally as a JSON file and displayed in a dedicated list view grouped by date.

## Data Model

```swift
struct BookmarkedWord: Identifiable, Codable {
    let id: UUID
    let spelling: String       // the word
    let sentence: String       // sentence containing the word
    let bookmarkedAt: Date     // timestamp
}
```

## Persistence

`BookmarkStore` — an `ObservableObject` backed by a JSON file at `<Documents>/bookmarks.json`.

Protocol: `BookmarkStoreProtocol` for testability.

```swift
protocol BookmarkStoreProtocol: ObservableObject {
    var bookmarks: [BookmarkedWord] { get }
    func add(spelling: String, sentence: String)
    func remove(id: UUID)
}
```

Methods:
- `add(spelling:sentence:)` — appends a new `BookmarkedWord` with current date and saves
- `remove(id:)` — removes by ID and saves
- On init, loads existing bookmarks from disk

## Bookmark Entry Point

In `SelectableAttributedTextView.Coordinator.editMenuForTextIn`, add a "收藏" `UIAction` alongside the existing "翻译" action.

Callback chain:
1. `SelectableAttributedTextView` gets `onBookmarkSelection: (String, String) -> Void` (word, sentence)
2. Inside the coordinator, when "收藏" is tapped:
   - Get selected text as the word
   - Extract the sentence containing the word from the full text using `NSString.enumerateSubstrings(options: .bySentences)`
3. `ArticleParagraphSection` passes the callback through
4. `ArticleReaderView` receives it and calls `BookmarkStore.add`

## Sentence Extraction

Given the full paragraph text and a selected word, find the sentence containing that word:

```
enumerateSubstrings(in: fullRange, options: .bySentences) { sentence, _, _, stop in
    if sentence contains the selected word (case-insensitive) {
        result = sentence
        stop = true
    }
}
```

## Bookmark List View

`BookmarkListView` — pushed via NavigationLink from TodayView toolbar.

Layout:
- Grouped by date (day granularity), sections ordered newest-first
- Section header: formatted date (e.g., "2026年4月13日")
- Each row: word spelling displayed prominently
- Tap a row: expand/collapse to show the extracted sentence below the word
- Swipe left to delete

## Navigation

In `TodayView` toolbar (leading position), add a star icon button that navigates to `BookmarkListView`.

## File Changes

| Action | File |
|--------|------|
| Create | `Models/BookmarkedWord.swift` |
| Create | `Services/BookmarkStore.swift` |
| Create | `Views/BookmarkListView.swift` |
| Modify | `Views/ArticleReaderView.swift` — add "收藏" to edit menu, sentence extraction, callback chain |
| Modify | `Views/TodayView.swift` — add star icon toolbar button + navigationDestination |

## Test Plan

- `BookmarkStoreTests` — add, remove, persistence round-trip, duplicate handling
- `BookmarkListView` — manual verification of grouping, expand/collapse, delete
- `ArticleReaderView` — manual verification of edit menu "收藏" action and sentence extraction
