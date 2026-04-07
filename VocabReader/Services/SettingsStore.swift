import Foundation
import Combine

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private enum Keys {
        static let maiMemoToken = "vocabreader.maimemo.token"
        static let llmAPIKey   = "vocabreader.llm.apikey"
        static let llmBaseURL  = "llmBaseURL"
        static let llmModel    = "llmModel"
    }

    @Published var maiMemoToken: String = ""
    @Published var llmAPIKey: String = ""
    @Published var llmBaseURL: String = ""
    @Published var llmModel: String = ""

    var isConfigured: Bool {
        !maiMemoToken.isEmpty && !llmAPIKey.isEmpty &&
        !llmBaseURL.isEmpty && !llmModel.isEmpty
    }

    init() {
        load()
    }

    func save() {
        Keychain.save(maiMemoToken, key: Keys.maiMemoToken)
        Keychain.save(llmAPIKey, key: Keys.llmAPIKey)
        UserDefaults.standard.set(llmBaseURL, forKey: Keys.llmBaseURL)
        UserDefaults.standard.set(llmModel, forKey: Keys.llmModel)
    }

    private func load() {
        maiMemoToken = Keychain.load(key: Keys.maiMemoToken) ?? ""
        llmAPIKey    = Keychain.load(key: Keys.llmAPIKey) ?? ""
        llmBaseURL   = UserDefaults.standard.string(forKey: Keys.llmBaseURL) ?? ""
        llmModel     = UserDefaults.standard.string(forKey: Keys.llmModel) ?? ""
    }
}
