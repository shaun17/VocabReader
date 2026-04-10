import Foundation
import Combine

struct SettingsStoreStorage {
    let defaults: UserDefaults
    let keychain: KeychainStore
    let maiMemoTokenKey: String
    let llmAPIKeyKey: String
    let llmBaseURLKey: String
    let llmModelKey: String
    let articleWordCountKey: String
    let wordsPerArticleKey: String
    let selectedTopicKey: String
    let enabledScenesKey: String

    static let app = SettingsStoreStorage(
        defaults: .standard,
        keychain: Keychain.appStore,
        maiMemoTokenKey: "vocabreader.maimemo.token",
        llmAPIKeyKey: "vocabreader.llm.apikey",
        llmBaseURLKey: "llmBaseURL",
        llmModelKey: "llmModel",
        articleWordCountKey: "articleWordCount",
        wordsPerArticleKey: "wordsPerArticle",
        selectedTopicKey: "selectedArticleTopic",
        enabledScenesKey: "enabledArticleScenes"
    )

    static func testing(namespace: String) -> SettingsStoreStorage {
        let suiteName = "com.vocabreader.tests.\(namespace)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard

        return SettingsStoreStorage(
            defaults: defaults,
            keychain: KeychainStore(
                service: "com.vocabreader.secure-storage.tests.\(namespace)",
                defaults: defaults,
                fallbackPrefix: "com.vocabreader.secure-storage.tests.\(namespace).fallback."
            ),
            maiMemoTokenKey: "vocabreader.tests.\(namespace).maimemo.token",
            llmAPIKeyKey: "vocabreader.tests.\(namespace).llm.apikey",
            llmBaseURLKey: "vocabreader.tests.\(namespace).llmBaseURL",
            llmModelKey: "vocabreader.tests.\(namespace).llmModel",
            articleWordCountKey: "vocabreader.tests.\(namespace).articleWordCount",
            wordsPerArticleKey: "vocabreader.tests.\(namespace).wordsPerArticle",
            selectedTopicKey: "vocabreader.tests.\(namespace).selectedArticleTopic",
            enabledScenesKey: "vocabreader.tests.\(namespace).enabledArticleScenes"
        )
    }
}

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var maiMemoToken: String = ""
    @Published var llmAPIKey: String = ""
    @Published var llmBaseURL: String = ""
    @Published var llmModel: String = ""
    @Published var articleWordCount: Int = 50
    @Published var wordsPerArticle: Int = 10
    @Published var selectedTopic: ArticleTopic = .general
    @Published var enabledScenes: [ArticleScene] = ArticleScene.allCases

    private let storage: SettingsStoreStorage

    var isConfigured: Bool {
        !maiMemoToken.isEmpty && !llmAPIKey.isEmpty &&
        !llmBaseURL.isEmpty && !llmModel.isEmpty
    }

    var llmConfig: LLMConfig {
        LLMConfig(
            apiKey: llmAPIKey,
            baseURL: llmBaseURL,
            model: llmModel
        )
    }

    var articleGenerationSettings: ArticleGenerationSettings {
        ArticleGenerationSettings(
            articleWordCount: articleWordCount,
            wordsPerArticle: wordsPerArticle,
            selectedTopic: selectedTopic,
            enabledScenes: enabledScenes
        )
    }

    init(storage: SettingsStoreStorage = .app) {
        self.storage = storage
        load()
    }

    func makeDraft() -> SettingsDraft {
        SettingsDraft(
            maiMemoToken: maiMemoToken,
            llmAPIKey: llmAPIKey,
            llmBaseURL: llmBaseURL,
            llmModel: llmModel,
            articleWordCount: articleWordCount,
            wordsPerArticle: wordsPerArticle,
            selectedTopic: selectedTopic,
            enabledScenes: enabledScenes
        )
    }

    /// 将草稿应用到内存中的设置对象，并统一做数值与体裁规范化。
    func apply(_ draft: SettingsDraft) {
        maiMemoToken = draft.maiMemoToken
        llmAPIKey = draft.llmAPIKey
        llmBaseURL = draft.llmBaseURL
        llmModel = draft.llmModel
        articleWordCount = Self.normalizedArticleWordCount(draft.articleWordCount)
        wordsPerArticle = Self.normalizedWordsPerArticle(draft.wordsPerArticle)
        selectedTopic = draft.selectedTopic
        enabledScenes = Self.normalizedEnabledScenes(draft.enabledScenes)
    }

    /// 将当前设置持久化到本地存储，供下次启动恢复。
    func save() {
        storage.keychain.save(maiMemoToken, key: storage.maiMemoTokenKey)
        storage.keychain.save(llmAPIKey, key: storage.llmAPIKeyKey)
        storage.defaults.set(llmBaseURL, forKey: storage.llmBaseURLKey)
        storage.defaults.set(llmModel, forKey: storage.llmModelKey)
        storage.defaults.set(articleWordCount, forKey: storage.articleWordCountKey)
        storage.defaults.set(wordsPerArticle, forKey: storage.wordsPerArticleKey)
        storage.defaults.set(selectedTopic.rawValue, forKey: storage.selectedTopicKey)
        storage.defaults.set(enabledScenes.map(\.rawValue), forKey: storage.enabledScenesKey)
    }

    /// 从本地存储恢复设置，并对历史值做兼容与规范化。
    private func load() {
        maiMemoToken = storage.keychain.load(key: storage.maiMemoTokenKey) ?? ""
        llmAPIKey    = storage.keychain.load(key: storage.llmAPIKeyKey) ?? ""
        llmBaseURL   = storage.defaults.string(forKey: storage.llmBaseURLKey) ?? ""
        llmModel     = storage.defaults.string(forKey: storage.llmModelKey) ?? ""
        let storedWordCount = storage.defaults.object(forKey: storage.articleWordCountKey) as? Int
        let storedWordsPerArticle = storage.defaults.object(forKey: storage.wordsPerArticleKey) as? Int
        articleWordCount = Self.normalizedArticleWordCount(storedWordCount ?? 50)
        wordsPerArticle = Self.normalizedWordsPerArticle(storedWordsPerArticle ?? 10)
        let storedTopic = storage.defaults.string(forKey: storage.selectedTopicKey)
        selectedTopic = ArticleTopic(rawValue: storedTopic ?? "") ?? .general
        let storedScenes = storage.defaults.stringArray(forKey: storage.enabledScenesKey) ?? []
        enabledScenes = Self.normalizedEnabledScenes(storedScenes.compactMap(ArticleScene.init(rawValue:)))
    }

    private static func normalizedArticleWordCount(_ value: Int) -> Int {
        let clamped = min(max(value, 10), 100)
        let rounded = ((clamped + 5) / 10) * 10
        return min(max(rounded, 10), 100)
    }

    private static func normalizedWordsPerArticle(_ value: Int) -> Int {
        let clamped = min(max(value, 5), 30)
        let rounded = ((clamped + 2) / 5) * 5
        return min(max(rounded, 5), 30)
    }

    /// 规范化体裁列表，兼容旧版本缺失值并维持固定展示顺序。
    private static func normalizedEnabledScenes(_ scenes: [ArticleScene]) -> [ArticleScene] {
        let normalizedScenes = ArticleScene.allCases.filter { scenes.contains($0) }
        return normalizedScenes.isEmpty ? ArticleScene.allCases : normalizedScenes
    }
}
