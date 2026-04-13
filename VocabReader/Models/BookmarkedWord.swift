import Foundation

struct BookmarkedWord: Identifiable, Codable, Equatable {
    let id: UUID
    let spelling: String
    let sentence: String
    let bookmarkedAt: Date
}
