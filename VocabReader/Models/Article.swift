import Foundation

struct Article: Identifiable {
    let id: UUID
    let scene: ArticleScene
    let content: String
    let targetWords: [VocabWord]
}

extension Article: Hashable {
    static func == (lhs: Article, rhs: Article) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
