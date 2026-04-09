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

    static let app = SettingsStoreStorage(
        defaults: .standard,
        keychain: Keychain.appStore,
        maiMemoTokenKey: "vocabreader.maimemo.token",
        llmAPIKeyKey: "vocabreader.llm.apikey",
        llmBaseURLKey: "llmBaseURL",
        llmModelKey: "llmModel",
        articleWordCountKey: "articleWordCount",
        wordsPerArticleKey: "wordsPerArticle"
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
            wordsPerArticleKey: "vocabreader.tests.\(namespace).wordsPerArticle"
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
            wordsPerArticle: wordsPerArticle
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
            wordsPerArticle: wordsPerArticle
        )
    }

    func apply(_ draft: SettingsDraft) {
        maiMemoToken = draft.maiMemoToken
        llmAPIKey = draft.llmAPIKey
        llmBaseURL = draft.llmBaseURL
        llmModel = draft.llmModel
        articleWordCount = Self.normalizedArticleWordCount(draft.articleWordCount)
        wordsPerArticle = Self.normalizedWordsPerArticle(draft.wordsPerArticle)
    }

    func save() {
        storage.keychain.save(maiMemoToken, key: storage.maiMemoTokenKey)
        storage.keychain.save(llmAPIKey, key: storage.llmAPIKeyKey)
        storage.defaults.set(llmBaseURL, forKey: storage.llmBaseURLKey)
        storage.defaults.set(llmModel, forKey: storage.llmModelKey)
        storage.defaults.set(articleWordCount, forKey: storage.articleWordCountKey)
        storage.defaults.set(wordsPerArticle, forKey: storage.wordsPerArticleKey)
    }

    private func load() {
        maiMemoToken = storage.keychain.load(key: storage.maiMemoTokenKey) ?? ""
        llmAPIKey    = storage.keychain.load(key: storage.llmAPIKeyKey) ?? ""
        llmBaseURL   = storage.defaults.string(forKey: storage.llmBaseURLKey) ?? ""
        llmModel     = storage.defaults.string(forKey: storage.llmModelKey) ?? ""
        let storedWordCount = storage.defaults.object(forKey: storage.articleWordCountKey) as? Int
        let storedWordsPerArticle = storage.defaults.object(forKey: storage.wordsPerArticleKey) as? Int
        articleWordCount = Self.normalizedArticleWordCount(storedWordCount ?? 50)
        wordsPerArticle = Self.normalizedWordsPerArticle(storedWordsPerArticle ?? 10)
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
}
