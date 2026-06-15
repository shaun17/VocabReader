import Foundation

struct Article: Identifiable {
    let id: UUID
    let scene: ArticleScene
    let topic: ArticleTopic
    let title: String
    let content: String
    let targetWords: [VocabWord]
    let vocabularyOccurrences: [ArticleVocabularyOccurrence]

    /// 创建文章模型，并允许旧调用点在未指定主题时回退到"通用"。
    init(
        id: UUID,
        scene: ArticleScene,
        topic: ArticleTopic = .general,
        title: String = "",
        content: String,
        targetWords: [VocabWord],
        vocabularyOccurrences: [ArticleVocabularyOccurrence] = []
    ) {
        self.id = id
        self.scene = scene
        self.topic = topic
        self.title = title
        self.content = content
        self.targetWords = targetWords
        self.vocabularyOccurrences = vocabularyOccurrences
    }
}

extension Article: Hashable {
    static func == (lhs: Article, rhs: Article) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct ArticleVocabularyOccurrence: Hashable {
    let word: VocabWord
    let surfaceText: String
    let range: NSRange

    static func == (lhs: ArticleVocabularyOccurrence, rhs: ArticleVocabularyOccurrence) -> Bool {
        lhs.word == rhs.word &&
            lhs.surfaceText == rhs.surfaceText &&
            lhs.range.location == rhs.range.location &&
            lhs.range.length == rhs.range.length
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(word)
        hasher.combine(surfaceText)
        hasher.combine(range.location)
        hasher.combine(range.length)
    }
}
