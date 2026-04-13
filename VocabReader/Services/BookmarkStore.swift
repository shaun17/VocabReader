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
