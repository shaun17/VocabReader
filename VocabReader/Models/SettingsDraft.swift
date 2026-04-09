import Foundation

struct SettingsDraft: Equatable {
    var maiMemoToken: String
    var llmAPIKey: String
    var llmBaseURL: String
    var llmModel: String
    var articleWordCount: Int
    var wordsPerArticle: Int

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
}
