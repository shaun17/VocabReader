import Foundation

struct ArticleParagraph: Identifiable, Hashable {
    let index: Int
    let content: String
    let vocabularyOccurrences: [ArticleVocabularyOccurrence]

    var id: Int { index }

    /// 创建段落模型，默认不带命中范围以兼容旧测试和手工构造数据。
    init(
        index: Int,
        content: String,
        vocabularyOccurrences: [ArticleVocabularyOccurrence] = []
    ) {
        self.index = index
        self.content = content
        self.vocabularyOccurrences = vocabularyOccurrences
    }
}
