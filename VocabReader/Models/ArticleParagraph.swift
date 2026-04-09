import Foundation

struct ArticleParagraph: Identifiable, Hashable {
    let index: Int
    let content: String

    var id: Int { index }
}
