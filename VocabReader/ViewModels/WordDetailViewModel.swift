import Foundation

@MainActor
final class WordDetailViewModel: ObservableObject {
    @Published var word: VocabWord?
    @Published var translation: String?
    @Published var isLoading = false
    @Published var error: String?

    private let translator: WordTranslatorServiceProtocol
    private var requestSequence = 0

    init(translator: WordTranslatorServiceProtocol) {
        self.translator = translator
    }

    func present(word: VocabWord) async {
        requestSequence += 1
        let requestID = requestSequence
        self.word = word
        isLoading = true
        error = nil
        translation = nil

        do {
            let translation = try await translator.translate(word: word.spelling)
            guard requestID == requestSequence else { return }
            self.translation = translation
        } catch {
            guard requestID == requestSequence else { return }
            self.error = error.localizedDescription
        }

        guard requestID == requestSequence else { return }
        isLoading = false
    }

    func dismiss() {
        requestSequence += 1
        word = nil
        translation = nil
        error = nil
        isLoading = false
    }
}
