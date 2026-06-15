import SwiftUI
import Translation
import UIKit

struct ArticleReaderView: View {
    let article: Article
    let translator: WordTranslatorServiceProtocol
    let paragraphTranslator: ArticleParagraphTranslatorProtocol

    @State private var translationText: String = ""
    @State private var showTranslation = false
    @State private var showBookmarkToast = false
    @State private var bookmarkToastPresentationID = 0
    @StateObject private var audioPlayer: ArticleAudioPlayerViewModel
    @ObservedObject private var bookmarkStore = BookmarkStore.shared
    private let formatter = ArticleContentFormatter()
    private let extractor = ArticleParagraphExtractor()
    private let paragraphs: [ArticleParagraph]

    init(article: Article, translator: WordTranslatorServiceProtocol, paragraphTranslator: ArticleParagraphTranslatorProtocol) {
        self.article = article
        self.translator = translator
        self.paragraphTranslator = paragraphTranslator
        let extracted = ArticleParagraphExtractor().extract(from: article)
        self.paragraphs = extracted
        _audioPlayer = StateObject(wrappedValue: ArticleAudioPlayerViewModel(paragraphs: extracted))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ArticleMetadataHeader(article: article)

                        if !article.title.isEmpty {
                            Text(article.title)
                                .font(.system(.title, design: .serif).italic())
                                .foregroundStyle(Color.readingTitle)
                        }

                        ForEach(paragraphs) { paragraph in
                            ArticleParagraphSection(
                                paragraph: paragraph,
                                targetWords: article.targetWords,
                                formatter: formatter,
                                translator: paragraphTranslator,
                                isHighlighted: audioPlayer.currentParagraphIndex == paragraph.index,
                                onWordTap: { spelling in
                                    translationText = spelling
                                    showTranslation = true
                                },
                                onTapParagraph: {
                                    audioPlayer.playFromParagraph(paragraph.index)
                                },
                                onBookmarkSelection: { packed in
                                    let parts = packed.split(separator: "\n", maxSplits: 1)
                                    let word = String(parts[0])
                                    let sentence = parts.count > 1 ? String(parts[1]) : word
                                    bookmarkStore.add(spelling: word, sentence: sentence)
                                    presentBookmarkSuccessToast()
                                }
                            )
                            .id(paragraph.index)
                        }
                    }
                    .padding()
                }
                .onChange(of: audioPlayer.currentParagraphIndex) { _, newIndex in
                    guard let newIndex else { return }
                    withAnimation {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }

            ArticlePlayerBar(player: audioPlayer)
        }
        .background { LinedPaperBackground() }
        .overlay(alignment: .top) {
            if showBookmarkToast {
                BookmarkSuccessToast()
                    .padding(.top, 12)
                    .padding(.horizontal, 20)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .navigationTitle(article.scene.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { audioPlayer.stop() }
        .task(id: bookmarkToastPresentationID) {
            guard bookmarkToastPresentationID > 0 else { return }

            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }

            withAnimation(.easeInOut(duration: 0.2)) {
                showBookmarkToast = false
            }
        }
        .modifier(
            TranslationPresentationCompatibilityModifier(
                isPresented: $showTranslation,
                text: translationText
            )
        )
    }

    /// 每次收藏都重新触发顶部提示；新的展示会自动取消上一轮 1 秒倒计时。
    private func presentBookmarkSuccessToast() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showBookmarkToast = true
        }
        bookmarkToastPresentationID += 1
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
        HStack(spacing: 12) {
            Label(article.scene.rawValue, systemImage: article.scene.systemImageName)
            Label(article.topic.rawValue, systemImage: article.topic.systemImageName)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BookmarkSuccessToast: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "star.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.readingTitle)

            Text("收藏成功")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background {
            Capsule(style: .continuous)
                .fill(Color.readingCardFill)
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color.readingRule.opacity(0.7), lineWidth: 0.8)
                }
        }
        .shadow(color: Color.black.opacity(0.08), radius: 8, y: 4)
    }
}

enum ParagraphSupplementDrawerMutation: Equatable {
    case open(token: Int)
    case close(token: Int)
}

struct ParagraphSupplementDrawerState<Supplement: Equatable>: Equatable {
    private(set) var renderedSupplement: Supplement?
    private(set) var isOpen = false
    private var token = 0

    /// 用单调递增 token 标记每次开合，避免关闭动画结束后误删后续新内容。
    mutating func update(with supplement: Supplement?) -> ParagraphSupplementDrawerMutation {
        token += 1
        let currentToken = token

        guard let supplement else {
            isOpen = false
            return .close(token: currentToken)
        }

        renderedSupplement = supplement
        isOpen = true
        return .open(token: currentToken)
    }

    /// 只有当前仍处于关闭状态且 token 匹配时，才真正清空渲染内容。
    mutating func finishClose(token closeToken: Int) {
        guard token == closeToken, !isOpen else { return }
        renderedSupplement = nil
    }
}

private enum ArticleParagraphSupplement: Equatable {
    case loading(String)
    case expanded(String)
    case error(String)
}

private struct ArticleParagraphSection: View {
    let paragraph: ArticleParagraph
    let targetWords: [VocabWord]
    let formatter: ArticleContentFormatter
    let isHighlighted: Bool
    let onWordTap: (String) -> Void
    let onTapParagraph: () -> Void
    let onBookmarkSelection: (String) -> Void

    @StateObject private var viewModel: ArticleParagraphTranslationViewModel
    @State private var drawerState = ParagraphSupplementDrawerState<ArticleParagraphSupplement>()
    private static let supplementAnimationDuration = 0.26

    init(
        paragraph: ArticleParagraph,
        targetWords: [VocabWord],
        formatter: ArticleContentFormatter,
        translator: ArticleParagraphTranslatorProtocol,
        isHighlighted: Bool = false,
        onWordTap: @escaping (String) -> Void,
        onTapParagraph: @escaping () -> Void = {},
        onBookmarkSelection: @escaping (String) -> Void = { _ in }
    ) {
        self.paragraph = paragraph
        self.targetWords = targetWords
        self.formatter = formatter
        self.isHighlighted = isHighlighted
        self.onWordTap = onWordTap
        self.onTapParagraph = onTapParagraph
        self.onBookmarkSelection = onBookmarkSelection
        _viewModel = StateObject(
            wrappedValue: ArticleParagraphTranslationViewModel(
                paragraph: paragraph.content,
                translator: translator
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SelectableAttributedTextView(
                attributedText: NSAttributedString(
                    formatter.formatParagraph(
                        content: paragraph.content,
                        targetWords: targetWords,
                        vocabularyOccurrences: paragraph.vocabularyOccurrences
                    )
                ),
                onOpenURL: { url in
                    if url.scheme == "word", let spelling = url.host(percentEncoded: false) {
                        onWordTap(spelling)
                    }
                },
                onBookmarkSelection: onBookmarkSelection,
                translationActionTitle: translationActionTitle,
                analysisActionTitle: analysisActionTitle,
                onTranslateAction: {
                    Task {
                        await viewModel.didTapTranslateButton()
                    }
                },
                onAnalyzeAction: {
                    Task {
                        await viewModel.didTapAnalyzeButton()
                    }
                }
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            if let renderedSupplement = drawerState.renderedSupplement {
                ParagraphSupplementDrawer(isOpen: drawerState.isOpen, animation: supplementAnimation) {
                    supplementContent(for: renderedSupplement)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHighlighted ? Color.readingTitle.opacity(0.08) : Color.clear)
        )
        .animation(.easeInOut(duration: 0.3), value: isHighlighted)
        .onAppear {
            updateSupplementDrawer(with: currentSupplement, animated: false)
        }
        .onChange(of: currentSupplement) { _, newSupplement in
            updateSupplementDrawer(with: newSupplement, animated: true)
        }
        .onTapGesture(count: 2) {
            onTapParagraph()
        }
    }

    private var translationActionTitle: String {
        viewModel.expandedPanel == .translation ? "收起" : "翻译"
    }

    private var analysisActionTitle: String {
        viewModel.expandedPanel == .analysis ? "收起" : "解析"
    }

    private var loadingMessage: String {
        switch viewModel.loadingPanel {
        case .translation:
            return "翻译中…"
        case .analysis:
            return "解析中…"
        case nil:
            return "加载中…"
        }
    }

    private var expandedText: String? {
        switch viewModel.expandedPanel {
        case .translation:
            return viewModel.translation
        case .analysis:
            return viewModel.analysis
        case nil:
            return nil
        }
    }

    private var supplementAnimation: Animation {
        .easeInOut(duration: Self.supplementAnimationDuration)
    }

    private var currentSupplement: ArticleParagraphSupplement? {
        if viewModel.isLoading {
            return .loading(loadingMessage)
        }

        if let expandedText {
            return .expanded(expandedText)
        }

        if let error = viewModel.error {
            return .error(error)
        }

        return nil
    }

    /// 外层只控制抽屉开合；内容在关闭动画结束前保留，避免文章先回流、旧内容再淡出。
    private func updateSupplementDrawer(with supplement: ArticleParagraphSupplement?, animated: Bool) {
        // 没有已渲染内容且新状态也是空时，不启动关闭计时，避免普通段落出现时产生多余状态更新。
        guard supplement != nil || drawerState.renderedSupplement != nil || drawerState.isOpen else { return }

        var mutation: ParagraphSupplementDrawerMutation?
        let updates = {
            mutation = drawerState.update(with: supplement)
        }

        if animated {
            withAnimation(supplementAnimation, updates)
        } else {
            updates()
        }

        guard case let .close(token) = mutation else { return }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Self.supplementAnimationDuration * 1_000_000_000))
            drawerState.finishClose(token: token)
        }
    }

    @ViewBuilder
    private func supplementContent(for supplement: ArticleParagraphSupplement) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            switch supplement {
            case .loading:
                loadingView
            case let .expanded(expandedText):
                expandedContentView(expandedText)
            case let .error(error):
                errorView(error)
            }
        }
    }

    private var loadingView: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text(loadingMessage)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    /// 让翻译和解析内容使用同一套容器样式，展开时只改变下方区域高度。
    private func expandedContentView(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.readingRule.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func errorView(_ error: String) -> some View {
        Text(error)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

private struct ParagraphSupplementDrawer<Content: View>: View {
    let isOpen: Bool
    let animation: Animation
    @ViewBuilder let content: () -> Content

    @State private var measuredHeight: CGFloat = 0

    var body: some View {
        content()
            .fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ParagraphSupplementHeightPreferenceKey.self,
                        value: proxy.size.height
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: isOpen ? measuredHeight : 0, alignment: .top)
            .clipped()
            .accessibilityHidden(!isOpen)
            .animation(animation, value: isOpen)
            .animation(animation, value: measuredHeight)
            .onPreferenceChange(ParagraphSupplementHeightPreferenceKey.self) { height in
                measuredHeight = height
            }
    }
}

private struct ParagraphSupplementHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    /// 多层内容同时上报高度时取最大值，确保抽屉边界包住完整内容。
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct SelectableAttributedTextView: UIViewRepresentable {
    let attributedText: NSAttributedString
    let onOpenURL: (URL) -> Void
    let onBookmarkSelection: (String) -> Void
    let translationActionTitle: String
    let analysisActionTitle: String
    let onTranslateAction: () -> Void
    let onAnalyzeAction: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onOpenURL: onOpenURL,
            onBookmarkSelection: onBookmarkSelection
        )
    }

    func makeUIView(context: Context) -> InlineActionTextContainer {
        let textView = InlineActionTextContainer()
        textView.delegate = context.coordinator
        return textView
    }

    func updateUIView(_ uiView: InlineActionTextContainer, context: Context) {
        let styledText = makeStyledAttributedText()
        if uiView.textView.attributedText != styledText {
            uiView.textView.attributedText = styledText
        }
        uiView.setActionTitles(
            translation: translationActionTitle,
            analysis: analysisActionTitle
        )
        uiView.onTranslateAction = onTranslateAction
        uiView.onAnalyzeAction = onAnalyzeAction
        context.coordinator.onOpenURL = onOpenURL
        context.coordinator.onBookmarkSelection = onBookmarkSelection
        uiView.invalidateIntrinsicContentSize()
        uiView.setNeedsLayout()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: InlineActionTextContainer, context: Context) -> CGSize? {
        let width = proposal.width ?? 0
        guard width > 0 else { return nil }

        return uiView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        )
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

    final class InlineActionTextContainer: UIView {
        let textView = UITextView()
        var onTranslateAction: (() -> Void)?
        var onAnalyzeAction: (() -> Void)?

        var delegate: UITextViewDelegate? {
            get { textView.delegate }
            set { textView.delegate = newValue }
        }

        private let translationButton = UIButton(type: .system)
        private let analysisButton = UIButton(type: .system)
        private let actionStack = UIStackView()

        override init(frame: CGRect) {
            super.init(frame: frame)
            configureTextView()
            configureActionButtons()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            configureTextView()
            configureActionButtons()
        }

        func setActionTitles(translation: String, analysis: String) {
            setTitle(translation, for: translationButton)
            setTitle(analysis, for: analysisButton)
            translationButton.accessibilityLabel = translation
            analysisButton.accessibilityLabel = analysis
            setNeedsLayout()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            applyLayout(for: bounds.width)
        }

        override func sizeThatFits(_ size: CGSize) -> CGSize {
            guard size.width > 0 else { return .zero }
            let layout = measuredLayout(for: size.width)
            return CGSize(width: size.width, height: layout.totalHeight)
        }

        /// 初始化正文 UITextView，保留选词、系统菜单和单词链接能力。
        private func configureTextView() {
            textView.isEditable = false
            textView.isSelectable = true
            textView.isScrollEnabled = false
            textView.backgroundColor = .clear
            textView.textColor = .label
            textView.textContainerInset = .zero
            textView.textContainer.lineFragmentPadding = 0
            textView.adjustsFontForContentSizeCategory = true
            textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
            addSubview(textView)
        }

        /// 初始化真实按钮，由容器负责把它们摆到正文最后一行后面。
        private func configureActionButtons() {
            let actionFont = UIFontMetrics(forTextStyle: .footnote)
                .scaledFont(for: UIFont.systemFont(ofSize: 13))

            [translationButton, analysisButton].forEach { button in
                var configuration = UIButton.Configuration.plain()
                configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 2, bottom: 4, trailing: 2)
                configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                    var outgoing = incoming
                    outgoing.font = actionFont
                    return outgoing
                }
                button.configuration = configuration
                button.titleLabel?.adjustsFontForContentSizeCategory = true
            }

            translationButton.addTarget(self, action: #selector(didTapTranslate), for: .touchUpInside)
            analysisButton.addTarget(self, action: #selector(didTapAnalyze), for: .touchUpInside)

            actionStack.axis = .horizontal
            actionStack.alignment = .center
            actionStack.spacing = 20
            actionStack.addArrangedSubview(translationButton)
            actionStack.addArrangedSubview(analysisButton)
            addSubview(actionStack)
        }

        private func setTitle(_ title: String, for button: UIButton) {
            var configuration = button.configuration ?? .plain()
            configuration.title = title
            button.configuration = configuration
        }

        @objc private func didTapTranslate() {
            onTranslateAction?()
        }

        @objc private func didTapAnalyze() {
            onAnalyzeAction?()
        }

        /// 根据最后一个 glyph 的位置计算按钮坐标；行尾空间不足时才自然换到下一行。
        private func measuredLayout(for width: CGFloat) -> (textHeight: CGFloat, actionFrame: CGRect, totalHeight: CGFloat) {
            let textHeight = measuredTextHeight(for: width)
            let actionSize = actionStack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            let line = lastLineLayout(width: width, textHeight: textHeight)
            let horizontalGap: CGFloat = 10
            let verticalGap: CGFloat = 2

            var actionX = line.endX + horizontalGap
            var actionY = line.rect.midY - actionSize.height / 2

            if actionX + actionSize.width > width {
                actionX = 0
                actionY = textHeight + verticalGap
            }

            actionY = max(0, actionY)

            return (
                textHeight: textHeight,
                actionFrame: CGRect(origin: CGPoint(x: actionX, y: actionY), size: actionSize),
                totalHeight: ceil(max(textHeight, actionY + actionSize.height))
            )
        }

        private func applyLayout(for width: CGFloat) {
            guard width > 0 else { return }
            let layout = measuredLayout(for: width)
            textView.frame = CGRect(x: 0, y: 0, width: width, height: layout.textHeight)
            actionStack.frame = layout.actionFrame
        }

        private func measuredTextHeight(for width: CGFloat) -> CGFloat {
            let targetSize = CGSize(width: width, height: .greatestFiniteMagnitude)
            return ceil(textView.sizeThatFits(targetSize).height)
        }

        private func lastLineLayout(width: CGFloat, textHeight: CGFloat) -> (endX: CGFloat, rect: CGRect) {
            textView.frame = CGRect(x: 0, y: 0, width: width, height: textHeight)
            textView.layoutManager.ensureLayout(for: textView.textContainer)

            let glyphCount = textView.layoutManager.numberOfGlyphs
            guard glyphCount > 0 else {
                return (0, CGRect(x: 0, y: 0, width: 0, height: textHeight))
            }

            let lastGlyphIndex = glyphCount - 1
            let lineRect = textView.layoutManager.lineFragmentUsedRect(
                forGlyphAt: lastGlyphIndex,
                effectiveRange: nil
            )
            let glyphRect = textView.layoutManager.boundingRect(
                forGlyphRange: NSRange(location: lastGlyphIndex, length: 1),
                in: textView.textContainer
            )

            return (ceil(glyphRect.maxX), lineRect)
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onOpenURL: (URL) -> Void
        var onBookmarkSelection: (String) -> Void

        init(
            onOpenURL: @escaping (URL) -> Void,
            onBookmarkSelection: @escaping (String) -> Void
        ) {
            self.onOpenURL = onOpenURL
            self.onBookmarkSelection = onBookmarkSelection
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
            // 双击选词时复用系统菜单，把自定义“收藏”插到 Lookup 前面，同时保留系统 translator。
            let selectedText = (textView.text as NSString).substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)

            guard !selectedText.isEmpty else {
                return UIMenu(children: suggestedActions)
            }

            let fullText = textView.text ?? ""
            let bookmarkAction = UIAction(title: "收藏", image: UIImage(systemName: "star")) { [onBookmarkSelection] _ in
                let sentence = SentenceExtractor.sentence(containing: selectedText, in: fullText)
                onBookmarkSelection(selectedText + "\n" + sentence)
            }

            return UIMenu(children: prioritizedMenuElements(from: suggestedActions, bookmarkAction: bookmarkAction))
        }

        /// 优先把“收藏”插到系统 Lookup 前面；如果当前系统菜单里没有 Lookup，就把“收藏”前置到最前面。
        private func prioritizedMenuElements(
            from suggestedActions: [UIMenuElement],
            bookmarkAction: UIAction
        ) -> [UIMenuElement] {
            let insertion = insertingBookmarkBeforeLookup(in: suggestedActions, bookmarkAction: bookmarkAction)
            if insertion.didInsertBookmark {
                return insertion.elements
            }

            return [bookmarkAction] + suggestedActions
        }

        /// 递归查找系统 Lookup 菜单，命中后把“收藏”插在它前面，避免误删系统 translator。
        private func insertingBookmarkBeforeLookup(
            in elements: [UIMenuElement],
            bookmarkAction: UIAction
        ) -> (elements: [UIMenuElement], didInsertBookmark: Bool) {
            var didInsertBookmark = false
            var updatedElements: [UIMenuElement] = []

            for element in elements {
                if let menu = element as? UIMenu {
                    if menu.identifier == .lookup {
                        updatedElements.append(bookmarkAction)
                        updatedElements.append(menu)
                        didInsertBookmark = true
                        continue
                    }

                    let insertion = insertingBookmarkBeforeLookup(in: menu.children, bookmarkAction: bookmarkAction)
                    if insertion.didInsertBookmark {
                        updatedElements.append(menu.replacingChildren(insertion.elements))
                        didInsertBookmark = true
                    } else {
                        updatedElements.append(menu)
                    }
                    continue
                }

                updatedElements.append(element)
            }

            return (updatedElements, didInsertBookmark)
        }
    }
}
