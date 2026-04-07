import SwiftUI

@main
struct VocabReaderApp: App {
    @StateObject private var settings = SettingsStore.shared

    var body: some Scene {
        WindowGroup {
            if settings.isConfigured {
                TodayView(generator: makeGenerator())
            } else {
                SettingsView(settings: settings, onSave: nil)
            }
        }
    }

    private func makeGenerator() -> ArticleGenerator {
        let maiMemo = MaiMemoService(token: settings.maiMemoToken)
        let llm = LLMService(config: LLMConfig(
            apiKey: settings.llmAPIKey,
            baseURL: settings.llmBaseURL,
            model: settings.llmModel
        ))
        return ArticleGenerator(maiMemo: maiMemo, llm: llm)
    }
}
