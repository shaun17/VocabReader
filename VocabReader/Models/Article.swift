import Foundation

struct Article: Identifiable {
    let id: UUID
    let scene: ArticleScene
    let topic: ArticleTopic
    let title: String
    let content: String
    let targetWords: [VocabWord]

    /// 创建文章模型，并允许旧调用点在未指定主题时回退到"通用"。
    init(
        id: UUID,
        scene: ArticleScene,
        topic: ArticleTopic = .general,
        title: String = "",
        content: String,
        targetWords: [VocabWord]
    ) {
        self.id = id
        self.scene = scene
        self.topic = topic
        self.title = title
        self.content = content
        self.targetWords = targetWords
    }
}

extension Article: Hashable {
    static func == (lhs: Article, rhs: Article) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
