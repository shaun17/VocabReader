import Foundation

@MainActor
final class WordDetailViewModel: ObservableObject {
    @Published var translation: String?
    @Published var isLoading = false
    @Published var error: String?

    private let word: VocabWord
    private let translator: WordTranslatorServiceProtocol

    init(word: VocabWord, translator: WordTranslatorServiceProtocol) {
        self.word = word
        self.translator = translator
    }

    func loadTranslation() async {
        isLoading = true
        error = nil
        translation = nil

        do {
            translation = try await translator.translate(word: word.spelling)
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}
