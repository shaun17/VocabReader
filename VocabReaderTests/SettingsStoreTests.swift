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

        let reloadedStore = SettingsStore(storage: storage)
        XCTAssertEqual(reloadedStore.maiMemoToken, "")
        XCTAssertEqual(reloadedStore.llmAPIKey, "")
        XCTAssertEqual(reloadedStore.llmBaseURL, "")
        XCTAssertEqual(reloadedStore.llmModel, "")
        XCTAssertEqual(reloadedStore.articleWordCount, 50)
        XCTAssertEqual(reloadedStore.wordsPerArticle, 10)
        XCTAssertEqual(reloadedStore.selectedTopic, .general)
        XCTAssertEqual(reloadedStore.enabledScenes, ArticleScene.allCases)
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
            enabledScenes: [.dialogue, .novel]
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
    }

    func testDefaultGenerationSettingsAreApplied() {
        let store = SettingsStore(storage: storage)

        XCTAssertEqual(store.articleWordCount, 50)
        XCTAssertEqual(store.wordsPerArticle, 10)
        XCTAssertEqual(store.selectedTopic, .general)
        XCTAssertEqual(store.enabledScenes, ArticleScene.allCases)
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
    }
}
