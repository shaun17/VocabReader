import SwiftUI
import Translation

struct ArticleReaderView: View {
    let article: Article
    let translator: WordTranslatorServiceProtocol
    let paragraphTranslator: ArticleParagraphTranslatorProtocol

    @State private var translationText: String = ""
    @State private var showTranslation = false
    private let formatter = ArticleContentFormatter()
    private let extractor = ArticleParagraphExtractor()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(extractor.extract(from: article)) { paragraph in
                    ArticleParagraphSection(
                        paragraph: paragraph,
                        targetWords: article.targetWords,
                        formatter: formatter,
                        translator: paragraphTranslator,
                        onWordTap: { spelling in
                            translationText = spelling
                            showTranslation = true
                        }
                    )
                }
            }
                .padding()
        }
        .navigationTitle(article.scene.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .translationPresentation(isPresented: $showTranslation, text: translationText)
    }
}

private struct ArticleParagraphSection: View {
    let paragraph: ArticleParagraph
    let targetWords: [VocabWord]
    let formatter: ArticleContentFormatter
    let onWordTap: (String) -> Void

    @StateObject private var viewModel: ArticleParagraphTranslationViewModel

    init(
        paragraph: ArticleParagraph,
        targetWords: [VocabWord],
        formatter: ArticleContentFormatter,
        translator: ArticleParagraphTranslatorProtocol,
        onWordTap: @escaping (String) -> Void
    ) {
        self.paragraph = paragraph
        self.targetWords = targetWords
        self.formatter = formatter
        self.onWordTap = onWordTap
        _viewModel = StateObject(
            wrappedValue: ArticleParagraphTranslationViewModel(
                paragraph: paragraph.content,
                translator: translator
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(
                formatter.formatParagraph(
                    content: paragraph.content,
                    targetWords: targetWords,
                    paragraphIndex: paragraph.index,
                    actionTitle: inlineActionTitle
                )
            )
                .font(.body)
                .lineSpacing(6)
                .environment(\.openURL, OpenURLAction { url in
                    if url.scheme == "paragraph", url.host(percentEncoded: false) == "\(paragraph.index)" {
                        Task {
                            await viewModel.didTapTranslateButton()
                        }
                        return .handled
                    }

                    if url.scheme == "word", let spelling = url.host(percentEncoded: false) {
                        onWordTap(spelling)
                        return .handled
                    }

                    return .discarded
                })

            if viewModel.isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("翻译中…")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            if let translation = viewModel.translation, viewModel.isExpanded {
                Text(translation)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else if let error = viewModel.error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var inlineActionTitle: String {
        viewModel.isExpanded ? "收起" : "翻译"
    }
}
