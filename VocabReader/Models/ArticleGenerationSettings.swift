import Foundation

struct ArticleGenerationSettings: Equatable {
    let articleWordCount: Int
    let wordsPerArticle: Int
    let selectedTopic: ArticleTopic
    let enabledScenes: [ArticleScene]

    init(
        articleWordCount: Int,
        wordsPerArticle: Int,
        selectedTopic: ArticleTopic = .general,
        enabledScenes: [ArticleScene] = ArticleScene.allCases
    ) {
        self.articleWordCount = articleWordCount
        self.wordsPerArticle = wordsPerArticle
        self.selectedTopic = selectedTopic
        self.enabledScenes = Self.normalizedEnabledScenes(enabledScenes)
    }

    /// 判断当前设置是否可以在不重载首页的前提下直接更新分页参数。
    func canUpdatePaginationInPlace(comparedTo previous: ArticleGenerationSettings) -> Bool {
        guard selectedTopic == previous.selectedTopic else { return false }
        guard enabledScenes == previous.enabledScenes else { return false }
        return articleWordCount != previous.articleWordCount || wordsPerArticle != previous.wordsPerArticle
    }

    /// 规范化体裁列表，既保持固定顺序，也保证至少有一个可用体裁。
    private static func normalizedEnabledScenes(_ scenes: [ArticleScene]) -> [ArticleScene] {
        let normalizedScenes = ArticleScene.allCases.filter { scenes.contains($0) }
        return normalizedScenes.isEmpty ? ArticleScene.allCases : normalizedScenes
    }
}
