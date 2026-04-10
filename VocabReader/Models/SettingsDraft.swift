import Foundation

struct SettingsDraft: Equatable {
    var maiMemoToken: String
    var llmAPIKey: String
    var llmBaseURL: String
    var llmModel: String
    var articleWordCount: Int
    var wordsPerArticle: Int
    var selectedTopic: ArticleTopic
    var enabledScenes: [ArticleScene]

    var isConfigured: Bool {
        !maiMemoToken.isEmpty &&
        !llmAPIKey.isEmpty &&
        !llmBaseURL.isEmpty &&
        !llmModel.isEmpty
    }

    var llmConfig: LLMConfig {
        LLMConfig(
            apiKey: llmAPIKey,
            baseURL: llmBaseURL,
            model: llmModel
        )
    }

    /// 判断某个体裁当前是否处于启用状态。
    func isSceneEnabled(_ scene: ArticleScene) -> Bool {
        enabledScenes.contains(scene)
    }

    /// 更新体裁开关，同时确保至少保留一个启用体裁。
    mutating func setSceneEnabled(_ isEnabled: Bool, for scene: ArticleScene) {
        if isEnabled {
            enabledScenes = ArticleScene.allCases.filter { enabledScenes.contains($0) || $0 == scene }
            return
        }

        let remainingScenes = enabledScenes.filter { $0 != scene }
        guard !remainingScenes.isEmpty else { return }
        enabledScenes = ArticleScene.allCases.filter { remainingScenes.contains($0) }
    }
}
