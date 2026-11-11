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
    let knownScenesKey: String
    let articleDifficultyKey: String
    let appearanceKey: String
    let speechEngineKey: String
    let phononVoiceKey: String

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
        enabledScenesKey: "enabledArticleScenes",
        knownScenesKey: "knownArticleScenes",
        articleDifficultyKey: "articleDifficulty",
        appearanceKey: "appAppearance",
        speechEngineKey: "speechEngine",
        phononVoiceKey: "phononVoice"
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
            enabledScenesKey: "vocabreader.tests.\(namespace).enabledArticleScenes",
            knownScenesKey: "vocabreader.tests.\(namespace).knownArticleScenes",
            articleDifficultyKey: "vocabreader.tests.\(namespace).articleDifficulty",
            appearanceKey: "vocabreader.tests.\(namespace).appAppearance",
            speechEngineKey: "vocabreader.tests.\(namespace).speechEngine",
            phononVoiceKey: "vocabreader.tests.\(namespace).phononVoice"
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
    @Published var articleDifficulty: ArticleDifficulty = .default
    @Published var appearance: AppAppearance = .system
    @Published var speechEngine: SpeechEngine = .system
    @Published var phononVoice: String = PhononVoice.defaultName

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
            enabledScenes: enabledScenes,
            difficulty: articleDifficulty
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
            enabledScenes: enabledScenes,
            articleDifficulty: articleDifficulty,
            appearance: appearance,
            speechEngine: speechEngine,
            phononVoice: phononVoice
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
        articleDifficulty = draft.articleDifficulty
        appearance = draft.appearance
        speechEngine = draft.speechEngine
        phononVoice = PhononVoice.normalizedName(draft.phononVoice)
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
        storage.defaults.set(ArticleScene.allCases.map(\.rawValue), forKey: storage.knownScenesKey)
        storage.defaults.set(articleDifficulty.rawValue, forKey: storage.articleDifficultyKey)
        storage.defaults.set(appearance.rawValue, forKey: storage.appearanceKey)
        storage.defaults.set(speechEngine.rawValue, forKey: storage.speechEngineKey)
        storage.defaults.set(phononVoice, forKey: storage.phononVoiceKey)
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
        let storedScenes = (storage.defaults.stringArray(forKey: storage.enabledScenesKey) ?? [])
            .compactMap(ArticleScene.init(rawValue:))
        let knownScenes = storage.defaults.stringArray(forKey: storage.knownScenesKey)?
            .compactMap(ArticleScene.init(rawValue:)) ?? ArticleScene.legacyCases
        // 升级前保存过体裁选择的用户，新增体裁默认开启；从未保存过的直接走默认全选。
        let addedScenes = storedScenes.isEmpty ? [] : ArticleScene.allCases.filter { !knownScenes.contains($0) }
        enabledScenes = Self.normalizedEnabledScenes(storedScenes + addedScenes)
        let storedDifficulty = storage.defaults.string(forKey: storage.articleDifficultyKey)
        articleDifficulty = ArticleDifficulty(rawValue: storedDifficulty ?? "") ?? .default
        let storedAppearance = storage.defaults.string(forKey: storage.appearanceKey)
        appearance = AppAppearance(rawValue: storedAppearance ?? "") ?? .system
        let storedSpeechEngine = storage.defaults.string(forKey: storage.speechEngineKey)
        speechEngine = SpeechEngine(rawValue: storedSpeechEngine ?? "") ?? .system
        phononVoice = PhononVoice.normalizedName(storage.defaults.string(forKey: storage.phononVoiceKey))
    }

    private static func normalizedArticleWordCount(_ value: Int) -> Int {
        ArticleGenerationLimits.normalizedArticleWordCount(value)
    }

    private static func normalizedWordsPerArticle(_ value: Int) -> Int {
        ArticleGenerationLimits.normalizedWordsPerArticle(value)
    }

    /// 规范化体裁列表，兼容旧版本缺失值并维持固定展示顺序。
    private static func normalizedEnabledScenes(_ scenes: [ArticleScene]) -> [ArticleScene] {
        let normalizedScenes = ArticleScene.allCases.filter { scenes.contains($0) }
        return normalizedScenes.isEmpty ? ArticleScene.allCases : normalizedScenes
    }
}
