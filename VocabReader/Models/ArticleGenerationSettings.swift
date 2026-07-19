import Foundation

enum ArticleGenerationLimits {
    static let articleWordCountRange = 10...500
    static let wordsPerArticleRange = 5...30
    static let articleWordCountStep = 10
    static let wordsPerArticleStep = 5

    /// 将今日总词汇量限制在产品允许范围内，并按设置页步长吸附。
    static func normalizedArticleWordCount(_ value: Int) -> Int {
        normalizedSteppedValue(
            value,
            range: articleWordCountRange,
            step: articleWordCountStep
        )
    }

    /// 将每篇词汇量限制在产品允许范围内，并按设置页步长吸附。
    static func normalizedWordsPerArticle(_ value: Int) -> Int {
        normalizedSteppedValue(
            value,
            range: wordsPerArticleRange,
            step: wordsPerArticleStep
        )
    }

    /// 统一处理数值下限、上限和步长，确保历史脏值或手输 0 不会进入生成流程。
    private static func normalizedSteppedValue(
        _ value: Int,
        range: ClosedRange<Int>,
        step: Int
    ) -> Int {
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        let rounded = ((clamped - range.lowerBound + step / 2) / step) * step + range.lowerBound
        return min(max(rounded, range.lowerBound), range.upperBound)
    }
}

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
