import Foundation

@MainActor
final class ArticleParagraphTranslationViewModel: ObservableObject {
    @Published var translation: String?
    @Published var isExpanded = false
    @Published var isLoading = false
    @Published var error: String?

    private let paragraph: String
    private let translator: ArticleParagraphTranslatorProtocol

    init(paragraph: String, translator: ArticleParagraphTranslatorProtocol) {
        self.paragraph = paragraph
        self.translator = translator
    }

    func didTapTranslateButton() async {
        guard !isLoading else { return }

        if translation != nil {
            isExpanded.toggle()
            return
        }

        isLoading = true
        error = nil

        do {
            translation = try await translator.translate(paragraph: paragraph)
            isExpanded = true
        } catch {
            self.error = error.localizedDescription
            isExpanded = false
        }

        isLoading = false
    }
}
