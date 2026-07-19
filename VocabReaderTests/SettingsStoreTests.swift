import XCTest
@testable import VocabReader

final class SettingsStoreTests: XCTestCase {
    private let storage = SettingsStoreStorage.testing(namespace: "settings-store-tests")

    override func setUp() {
        super.setUp()
        clearStoredSettings()
    }

    override func tearDown() {
        clearStoredSettings()
        super.tearDown()
    }

    func testSavePersistsAllUserInputs() {
        let store = SettingsStore(storage: storage)
        store.maiMemoToken = "maimemo-token"
        store.llmAPIKey = "llm-api-key"
        store.llmBaseURL = "https://api.moonshot.cn/v1"
        store.llmModel = "kimi-k2.5"
        store.articleWordCount = 30
        store.wordsPerArticle = 15
        store.selectedTopic = .medical
        store.enabledScenes = [.dialogue, .science]
        store.appearance = .dark

        store.save()

        let reloadedStore = SettingsStore(storage: storage)
        XCTAssertEqual(reloadedStore.maiMemoToken, "maimemo-token")
        XCTAssertEqual(reloadedStore.llmAPIKey, "llm-api-key")
        XCTAssertEqual(reloadedStore.llmBaseURL, "https://api.moonshot.cn/v1")
        XCTAssertEqual(reloadedStore.llmModel, "kimi-k2.5")
        XCTAssertEqual(reloadedStore.articleWordCount, 30)
        XCTAssertEqual(reloadedStore.wordsPerArticle, 15)
        XCTAssertEqual(reloadedStore.selectedTopic, .medical)
        XCTAssertEqual(reloadedStore.enabledScenes, [.dialogue, .science])
        XCTAssertEqual(reloadedStore.appearance, .dark)
    }

    func testSaveRestoresConfiguredStateAfterRelaunch() {
        let store = SettingsStore(storage: storage)
        store.maiMemoToken = "token"
        store.llmAPIKey = "key"
        store.llmBaseURL = "https://api.example.com/v1"
        store.llmModel = "kimi"
        store.articleWordCount = 20
        store.wordsPerArticle = 10
        store.selectedTopic = .ai
        store.enabledScenes = [.science]

        store.save()

        let reloadedStore = SettingsStore(storage: storage)
        XCTAssertTrue(reloadedStore.isConfigured)
        XCTAssertEqual(reloadedStore.selectedTopic, .ai)
        XCTAssertEqual(reloadedStore.enabledScenes, [.science])
    }

    func testPropertyChangesDoNotPersistWithoutExplicitSave() {
        let store = SettingsStore(storage: storage)
        store.maiMemoToken = "maimemo-token"
        store.llmAPIKey = "llm-api-key"
        store.llmBaseURL = "https://api.moonshot.cn/v1"
        store.llmModel = "kimi-k2.5"
        store.articleWordCount = 40
        store.wordsPerArticle = 20
        store.selectedTopic = .customer
        store.enabledScenes = [.dialogue]
        store.appearance = .light

        let reloadedStore = SettingsStore(storage: storage)
        XCTAssertEqual(reloadedStore.maiMemoToken, "")
        XCTAssertEqual(reloadedStore.llmAPIKey, "")
        XCTAssertEqual(reloadedStore.llmBaseURL, "")
        XCTAssertEqual(reloadedStore.llmModel, "")
        XCTAssertEqual(reloadedStore.articleWordCount, 50)
        XCTAssertEqual(reloadedStore.wordsPerArticle, 10)
        XCTAssertEqual(reloadedStore.selectedTopic, .general)
        XCTAssertEqual(reloadedStore.enabledScenes, ArticleScene.allCases)
        XCTAssertEqual(reloadedStore.appearance, .system)
    }

    func testApplyDraftUpdatesInMemoryStoreWithoutSaving() {
        let store = SettingsStore(storage: storage)
        let draft = SettingsDraft(
            maiMemoToken: "maimemo-token",
            llmAPIKey: "llm-api-key",
            llmBaseURL: "https://api.moonshot.cn/v1",
            llmModel: "kimi-k2.5",
            articleWordCount: 40,
            wordsPerArticle: 20,
            selectedTopic: .technology,
            enabledScenes: [.dialogue, .novel],
            appearance: .dark
        )

        store.apply(draft)

        XCTAssertEqual(store.maiMemoToken, "maimemo-token")
        XCTAssertEqual(store.llmAPIKey, "llm-api-key")
        XCTAssertEqual(store.llmBaseURL, "https://api.moonshot.cn/v1")
        XCTAssertEqual(store.llmModel, "kimi-k2.5")
        XCTAssertEqual(store.articleWordCount, 40)
        XCTAssertEqual(store.wordsPerArticle, 20)
        XCTAssertEqual(store.selectedTopic, .technology)
        XCTAssertEqual(store.enabledScenes, [.dialogue, .novel])
        XCTAssertEqual(store.appearance, .dark)
    }

    func testDefaultGenerationSettingsAreApplied() {
        let store = SettingsStore(storage: storage)

        XCTAssertEqual(store.articleWordCount, 50)
        XCTAssertEqual(store.wordsPerArticle, 10)
        XCTAssertEqual(store.selectedTopic, .general)
        XCTAssertEqual(store.enabledScenes, ArticleScene.allCases)
        XCTAssertEqual(store.appearance, .system)
    }

    /// 历史版本没有外观值时必须默认跟随系统，不应擅自锁定浅色或深色。
    func testMissingAppearanceDefaultsToSystem() {
        let store = SettingsStore(storage: storage)

        XCTAssertEqual(store.appearance, .system)
        XCTAssertEqual(store.appearance.userInterfaceStyle, .unspecified)
    }

    /// 无法识别的持久化值需要安全回退，避免升级后界面停留在错误外观。
    func testInvalidStoredAppearanceFallsBackToSystem() {
        storage.defaults.set("unknown", forKey: storage.appearanceKey)

        let store = SettingsStore(storage: storage)

        XCTAssertEqual(store.appearance, .system)
    }

    /// 手动选择浅色或深色时映射为明确窗口外观，从而覆盖设备主题。
    func testAppearanceMapsToWindowInterfaceStyle() {
        XCTAssertEqual(AppAppearance.light.userInterfaceStyle, .light)
        XCTAssertEqual(AppAppearance.dark.userInterfaceStyle, .dark)
    }

    /// 今日总词量上限提升到 500，单篇目标词量仍压到 30 的可读上限。
    func testApplyDraftCapsGenerationLimitsForReadableArticles() {
        let store = SettingsStore(storage: storage)
        let draft = SettingsDraft(
            maiMemoToken: "maimemo-token",
            llmAPIKey: "llm-api-key",
            llmBaseURL: "https://api.moonshot.cn/v1",
            llmModel: "kimi-k2.5",
            articleWordCount: 501,
            wordsPerArticle: 52,
            selectedTopic: .general,
            enabledScenes: ArticleScene.allCases
        )

        store.apply(draft)

        XCTAssertEqual(store.articleWordCount, 500)
        XCTAssertEqual(store.wordsPerArticle, 30)
    }

    /// 单篇目标词过多会逼模型写成词表例句，这里把上限恢复到 30。
    func testApplyDraftCapsWordsPerArticleAtThirty() {
        let store = SettingsStore(storage: storage)
        let draft = SettingsDraft(
            maiMemoToken: "maimemo-token",
            llmAPIKey: "llm-api-key",
            llmBaseURL: "https://api.moonshot.cn/v1",
            llmModel: "kimi-k2.5",
            articleWordCount: 200,
            wordsPerArticle: 50,
            selectedTopic: .general,
            enabledScenes: ArticleScene.allCases
        )

        store.apply(draft)

        XCTAssertEqual(store.wordsPerArticle, 30)
    }

    func testApplyDraftKeepsGenerationCountsAboveZero() {
        let store = SettingsStore(storage: storage)
        let draft = SettingsDraft(
            maiMemoToken: "maimemo-token",
            llmAPIKey: "llm-api-key",
            llmBaseURL: "https://api.moonshot.cn/v1",
            llmModel: "kimi-k2.5",
            articleWordCount: 0,
            wordsPerArticle: 0,
            selectedTopic: .general,
            enabledScenes: ArticleScene.allCases
        )

        store.apply(draft)

        XCTAssertEqual(store.articleWordCount, 10)
        XCTAssertEqual(store.wordsPerArticle, 5)
    }

    /// 四类设置必须通过同一展示模型提供标题、说明和图标，避免页面再次出现不同分区各写一套样式。
    func testSettingsPanelsUseOneSharedInformationArchitecture() {
        XCTAssertEqual(
            SettingsPanel.allCases.map(\.title),
            ["外观主题", "文章设置", "墨墨词库", "文章生成模型"]
        )
        XCTAssertEqual(
            SettingsPanel.allCases.map(\.systemImage),
            ["circle.lefthalf.filled", "text.book.closed", "books.vertical", "sparkles"]
        )
        XCTAssertTrue(SettingsPanel.allCases.allSatisfy { !$0.subtitle.isEmpty })
    }

    private func clearStoredSettings() {
        storage.keychain.delete(key: storage.maiMemoTokenKey)
        storage.keychain.delete(key: storage.llmAPIKeyKey)
        storage.defaults.removeObject(forKey: storage.llmBaseURLKey)
        storage.defaults.removeObject(forKey: storage.llmModelKey)
        storage.defaults.removeObject(forKey: storage.articleWordCountKey)
        storage.defaults.removeObject(forKey: storage.wordsPerArticleKey)
        storage.defaults.removeObject(forKey: storage.selectedTopicKey)
        storage.defaults.removeObject(forKey: storage.enabledScenesKey)
        storage.defaults.removeObject(forKey: storage.appearanceKey)
    }
}
