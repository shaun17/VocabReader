import SwiftUI
import Translation
import UIKit

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
                ArticleMetadataHeader(article: article)

                if !article.title.isEmpty {
                    Text(article.title)
                        .font(.system(.title, design: .serif).italic())
                        .foregroundStyle(Color.readingTitle)
                }

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
        .background(Color.readingBackground)
        .navigationTitle(article.scene.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .modifier(
            TranslationPresentationCompatibilityModifier(
                isPresented: $showTranslation,
                text: translationText
            )
        )
    }
}

private struct TranslationPresentationCompatibilityModifier: ViewModifier {
    @Binding var isPresented: Bool
    let text: String

    /// 在支持的系统版本上启用系统翻译面板，低版本则保持页面可正常编译运行。
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 17.4, *) {
            content.translationPresentation(isPresented: $isPresented, text: text)
        } else {
            content
        }
    }
}

private struct ArticleMetadataHeader: View {
    let article: Article

    var body: some View {
        HStack(spacing: 8) {
            ArticleMetadataBadge(
                title: article.scene.rawValue,
                systemImage: article.scene.systemImageName
            )
            ArticleMetadataBadge(
                title: article.topic.rawValue,
                systemImage: article.topic.systemImageName
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ArticleMetadataBadge: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.secondarySystemBackground), in: Capsule())
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
            SelectableAttributedTextView(
                attributedText: NSAttributedString(
                    formatter.formatParagraph(
                        content: paragraph.content,
                        targetWords: targetWords,
                        paragraphIndex: paragraph.index,
                        actionTitle: inlineActionTitle
                    )
                ),
                onOpenURL: { url in
                    if url.scheme == "paragraph", url.host(percentEncoded: false) == "\(paragraph.index)" {
                        Task {
                            await viewModel.didTapTranslateButton()
                        }
                        return
                    }

                    if url.scheme == "word", let spelling = url.host(percentEncoded: false) {
                        onWordTap(spelling)
                    }
                },
                onTranslateSelection: { selectedText in
                    onWordTap(selectedText)
                }
            )
            .frame(maxWidth: .infinity, alignment: .leading)

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
                    .textSelection(.enabled)
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

private struct SelectableAttributedTextView: UIViewRepresentable {
    let attributedText: NSAttributedString
    let onOpenURL: (URL) -> Void
    let onTranslateSelection: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onOpenURL: onOpenURL,
            onTranslateSelection: onTranslateSelection
        )
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.font = bodyFont
        textView.textColor = .label
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = true
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        let styledText = makeStyledAttributedText()
        if uiView.attributedText != styledText {
            uiView.attributedText = styledText
        }
        context.coordinator.onOpenURL = onOpenURL
        context.coordinator.onTranslateSelection = onTranslateSelection
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 0
        guard width > 0 else { return nil }

        let targetSize = CGSize(width: width, height: .greatestFiniteMagnitude)
        let fittingSize = uiView.sizeThatFits(targetSize)
        return CGSize(width: width, height: fittingSize.height)
    }

    private func makeStyledAttributedText() -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: attributedText)
        let fullRange = NSRange(location: 0, length: mutable.length)

        guard fullRange.length > 0 else { return mutable }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 6
        mutable.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)

        let bodyFont = self.bodyFont
        mutable.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            guard value == nil else { return }
            mutable.addAttribute(.font, value: bodyFont, range: range)
        }

        let inlineActionFont = UIFontMetrics(forTextStyle: .footnote)
            .scaledFont(for: UIFont.systemFont(ofSize: 13))
        mutable.enumerateAttribute(.link, in: fullRange) { value, range, _ in
            guard
                let url = value as? URL,
                url.scheme == "paragraph"
            else { return }

            mutable.addAttribute(.font, value: inlineActionFont, range: range)
        }

        return mutable
    }

    private var bodyFont: UIFont {
        // 正文统一使用衬线字体，提升英文长文阅读质感并贴近杂志排版。
        let baseFont = UIFont.preferredFont(forTextStyle: .body)
        let serifDescriptor = baseFont.fontDescriptor.withDesign(.serif) ?? baseFont.fontDescriptor
        let serifFont = UIFont(descriptor: serifDescriptor, size: baseFont.pointSize + 2)
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: serifFont)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onOpenURL: (URL) -> Void
        var onTranslateSelection: (String) -> Void

        init(
            onOpenURL: @escaping (URL) -> Void,
            onTranslateSelection: @escaping (String) -> Void
        ) {
            self.onOpenURL = onOpenURL
            self.onTranslateSelection = onTranslateSelection
        }

        func textView(
            _ textView: UITextView,
            shouldInteractWith url: URL,
            in characterRange: NSRange,
            interaction: UITextItemInteraction
        ) -> Bool {
            onOpenURL(url)
            return false
        }

        func textView(
            _ textView: UITextView,
            editMenuForTextIn range: NSRange,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            let selectedText = (textView.text as NSString).substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)

            guard !selectedText.isEmpty else {
                return UIMenu(children: suggestedActions)
            }

            let translateAction = UIAction(title: "翻译") { [onTranslateSelection] _ in
                onTranslateSelection(selectedText)
            }

            return UIMenu(children: suggestedActions + [translateAction])
        }
    }
}
