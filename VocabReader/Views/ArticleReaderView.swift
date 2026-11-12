import SwiftUI
import UIKit

struct ArticleReaderView: View {
    let article: Article
    let translator: WordLookupServiceProtocol
    let paragraphTranslator: ArticleParagraphTranslatorProtocol

    @State private var wordLookup: WordLookupRequest?
    @State private var showBookmarkToast = false
    @State private var bookmarkToastPresentationID = 0
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @StateObject private var audioPlayer: ArticleAudioPlayerViewModel
    @ObservedObject private var bookmarkStore = BookmarkStore.shared
    private let formatter = ArticleContentFormatter()
    private let extractor = ArticleParagraphExtractor()
    private let paragraphs: [ArticleParagraph]

    init(article: Article, translator: WordLookupServiceProtocol, paragraphTranslator: ArticleParagraphTranslatorProtocol) {
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
                    // 整篇文章是一张手绘纸片：首页那张卡片展开后的样子，同一个种子保证轮廓气质一致。
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ArticleSheetHeader(article: article, seed: articleSeed)
                            .padding(.horizontal, 8)

                        SketchDivider(seed: articleSeed &+ 3)
                            .padding(.horizontal, 8)

                        ForEach(paragraphs) { paragraph in
                            ArticleParagraphSection(
                                paragraph: paragraph,
                                targetWords: article.targetWords,
                                formatter: formatter,
                                translator: paragraphTranslator,
                                sketchSeed: articleSeed &+ UInt64(paragraph.index + 1),
                                emphasizesSpeakers: article.scene.usesSpeakerLines,
                                isHighlighted: audioPlayer.currentParagraphIndex == paragraph.index,
                                onWordTap: { request in
                                    wordLookup = request
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
                    .padding(.horizontal, 10)
                    .padding(.vertical, 18)
                    .background {
                        ReadingCardBackground(seed: articleSeed)
                    }
                    // 展开屏上限制行宽，避免一行英文拉得过长。
                    .frame(maxWidth: ArticleSheetMetrics.maxWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 24)
                }
                .onChange(of: audioPlayer.currentParagraphIndex) { _, newIndex in
                    guard let newIndex else { return }
                    if accessibilityReduceMotion {
                        proxy.scrollTo(newIndex, anchor: .center)
                    } else {
                        withAnimation {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
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
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
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
        .sheet(item: $wordLookup) { request in
            WordLookupSheet(
                request: request,
                service: translator,
                isArticleAudioActive: { [audioPlayer] in audioPlayer.playbackState != .idle }
            )
        }
    }

    private var articleSeed: UInt64 {
        SketchSeed.make(article.id)
    }

    /// 每次收藏都重新触发顶部提示；新的展示会自动取消上一轮 1 秒倒计时。
    private func presentBookmarkSuccessToast() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showBookmarkToast = true
        }
        bookmarkToastPresentationID += 1
    }
}

enum ArticleSheetMetrics {
    static let maxWidth: CGFloat = 720
}

/// 纸片顶部：体裁/主题标签、马克笔标题，目标词默认收起，只占一行。
private struct ArticleSheetHeader: View {
    let article: Article
    let seed: UInt64

    @State private var showsWords = false
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Label(article.scene.rawValue, systemImage: article.scene.systemImageName)
                Label(article.topic.rawValue, systemImage: article.topic.systemImageName)
            }
            .font(.caption)
            .foregroundStyle(Color.readingTextSecondary)

            if !article.title.isEmpty {
                Text(article.title)
                    .font(.system(.title2, design: .serif).italic().weight(.semibold))
                    .foregroundStyle(Color.readingTitle)
                    .markerHighlight(seed: seed)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !article.targetWords.isEmpty {
                wordsDisclosure
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var wordsDisclosure: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(accessibilityReduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    showsWords.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Text("\(article.targetWords.count) 个词汇")
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(showsWords ? 180 : 0))
                }
                .font(.caption)
                .foregroundStyle(Color.readingTextTertiary)
                .frame(minHeight: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(showsWords ? "收起目标词" : "展开目标词")

            if showsWords {
                Text(article.targetWords.map(\.spelling).joined(separator: " · "))
                    .font(.system(.footnote, design: .serif).italic())
                    .foregroundStyle(Color.readingTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
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
                .foregroundStyle(Color.readingTextPrimary)
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
    let sketchSeed: UInt64
    let emphasizesSpeakers: Bool
    let isHighlighted: Bool
    let onWordTap: (WordLookupRequest) -> Void
    let onTapParagraph: () -> Void
    let onBookmarkSelection: (String) -> Void

    @StateObject private var viewModel: ArticleParagraphTranslationViewModel
    @State private var drawerState = ParagraphSupplementDrawerState<ArticleParagraphSupplement>()
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    private static let supplementAnimationDuration = 0.26

    init(
        paragraph: ArticleParagraph,
        targetWords: [VocabWord],
        formatter: ArticleContentFormatter,
        translator: ArticleParagraphTranslatorProtocol,
        sketchSeed: UInt64 = 0,
        emphasizesSpeakers: Bool = false,
        isHighlighted: Bool = false,
        onWordTap: @escaping (WordLookupRequest) -> Void,
        onTapParagraph: @escaping () -> Void = {},
        onBookmarkSelection: @escaping (String) -> Void = { _ in }
    ) {
        self.paragraph = paragraph
        self.targetWords = targetWords
        self.formatter = formatter
        self.sketchSeed = sketchSeed
        self.emphasizesSpeakers = emphasizesSpeakers
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
        VStack(alignment: .leading, spacing: 0) {
            SelectableAttributedTextView(
                attributedText: NSAttributedString(
                    formatter.formatParagraph(
                        content: paragraph.content,
                        targetWords: targetWords,
                        vocabularyOccurrences: paragraph.vocabularyOccurrences
                    )
                ),
                emphasizesSpeakers: emphasizesSpeakers,
                onOpenURL: { url in
                    if url.scheme == "word", let spelling = url.host(percentEncoded: false) {
                        onWordTap(lookupRequest(for: spelling))
                    }
                },
                onBookmarkSelection: onBookmarkSelection,
                onTranslateSelection: { selection in
                    onWordTap(lookupRequest(for: selection))
                },
                translationActionPresentation: supplementPresentation(for: .translation),
                analysisActionPresentation: supplementPresentation(for: .analysis),
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
                SupplementDrawer(isOpen: drawerState.isOpen, animation: supplementAnimation) {
                    supplementContent(for: renderedSupplement)
                }
                .transition(.identity)
            }
        }
        .padding(8)
        .background {
            // 朗读中的段落用一块手绘形状的淡荧光底，和标题、目标词的马克笔语言一致。
            SketchOutlineShape(seed: sketchSeed, cornerRadius: 12, cornerVariance: 4, jitter: 1)
                .fill(Color.readingMarker.opacity(isHighlighted ? 0.2 : 0))
        }
        .animation(
            accessibilityReduceMotion ? nil : .easeInOut(duration: 0.3),
            value: isHighlighted
        )
        .onAppear {
            updateSupplementDrawer(with: currentSupplement)
        }
        .onChange(of: currentSupplement) { _, newSupplement in
            updateSupplementDrawer(with: newSupplement)
        }
        .onTapGesture(count: 2) {
            onTapParagraph()
        }
    }

    /// 将文章段落状态映射到与收藏页一致的阅读辅助按钮展示模型。
    /// 查词时带上所在原句和是否为今日目标词，供查词面板展示文中释义与原句翻译。
    private func lookupRequest(for text: String) -> WordLookupRequest {
        WordLookupRequest(
            text: text,
            sentence: Self.removingSpeakerLabel(
                from: SentenceExtractor.sentence(containing: text, in: paragraph.content)
            ),
            isTargetWord: targetWords.contains { $0.spelling.caseInsensitiveCompare(text) == .orderedSame }
        )
    }

    /// 对话体的原句去掉开头的 "Name:"，查词面板里只留句子本身。
    private static func removingSpeakerLabel(from sentence: String) -> String {
        sentence.replacingOccurrences(
            of: #"^[A-Z][A-Za-z'.\-]{0,19}(?: [A-Z][A-Za-z'.\-]{0,19})?\s*:\s*"#,
            with: "",
            options: .regularExpression
        )
    }

    private func supplementPresentation(for action: ReadingSupplementAction) -> ReadingSupplementActionPresentation {
        let panel: ArticleParagraphExpansionPanel = action == .translation ? .translation : .analysis
        let isLoading = viewModel.loadingPanel == panel
        return ReadingSupplementActionPresentation(
            action: action,
            isActive: viewModel.expandedPanel == panel || isLoading,
            isLoading: isLoading,
            isDisabled: viewModel.isLoading
        )
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

    private var supplementAnimation: Animation? {
        accessibilityReduceMotion ? nil : .easeInOut(duration: Self.supplementAnimationDuration)
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
    private func updateSupplementDrawer(with supplement: ArticleParagraphSupplement?) {
        // 没有已渲染内容且新状态也是空时，不启动关闭计时，避免普通段落出现时产生多余状态更新。
        guard supplement != nil || drawerState.renderedSupplement != nil || drawerState.isOpen else { return }

        let mutation = withAnimation(supplementAnimation) {
            drawerState.update(with: supplement)
        }

        guard case let .close(token) = mutation else { return }

        Task { @MainActor in
            if !accessibilityReduceMotion {
                try? await Task.sleep(
                    nanoseconds: UInt64(Self.supplementAnimationDuration * 1_000_000_000)
                )
            }
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
        .foregroundStyle(Color.readingTextSecondary)
    }

    /// 让翻译和解析内容使用同一套容器样式，展开时只改变下方区域高度。
    private func expandedContentView(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(Color.readingTextSecondary)
            .textSelection(.enabled)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                // 翻译 / 解析像夹在段落下的一张手绘便签。
                ReadingCardBackground(
                    seed: sketchSeed &+ 7,
                    fill: .readingControlFill,
                    cornerRadius: 10,
                    cornerVariance: 3,
                    lineOpacity: 0.7
                )
            }
    }

    private func errorView(_ error: String) -> some View {
        Text(error)
            .font(.footnote)
            .foregroundStyle(Color.readingError)
    }
}

private struct SelectableAttributedTextView: UIViewRepresentable {
    let attributedText: NSAttributedString
    var emphasizesSpeakers = false
    let onOpenURL: (URL) -> Void
    let onBookmarkSelection: (String) -> Void
    var onTranslateSelection: (String) -> Void = { _ in }
    let translationActionPresentation: ReadingSupplementActionPresentation
    let analysisActionPresentation: ReadingSupplementActionPresentation
    let onTranslateAction: () -> Void
    let onAnalyzeAction: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onOpenURL: onOpenURL,
            onBookmarkSelection: onBookmarkSelection,
            onTranslateSelection: onTranslateSelection
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
        uiView.setActionPresentations(
            translation: translationActionPresentation,
            analysis: analysisActionPresentation
        )
        uiView.onTranslateAction = onTranslateAction
        uiView.onAnalyzeAction = onAnalyzeAction
        context.coordinator.onOpenURL = onOpenURL
        context.coordinator.onBookmarkSelection = onBookmarkSelection
        context.coordinator.onTranslateSelection = onTranslateSelection
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

        mutable.enumerateAttribute(.foregroundColor, in: fullRange) { value, range, _ in
            guard value == nil else { return }
            mutable.addAttribute(.foregroundColor, value: ReadingPalette.primaryText, range: range)
        }

        if emphasizesSpeakers {
            emphasizeSpeakerLabels(in: mutable, bodyFont: bodyFont)
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

    /// 对话 / 访谈每行开头的 "Name:" 加粗并降一级颜色，方便扫读轮次。
    private func emphasizeSpeakerLabels(in text: NSMutableAttributedString, bodyFont: UIFont) {
        guard let regex = try? NSRegularExpression(
            pattern: #"^[A-Z][A-Za-z'.\-]{0,19}(?: [A-Z][A-Za-z'.\-]{0,19})?\s*:"#,
            options: [.anchorsMatchLines]
        ) else { return }

        let boldDescriptor = bodyFont.fontDescriptor.withSymbolicTraits(.traitBold) ?? bodyFont.fontDescriptor
        let speakerFont = UIFont(descriptor: boldDescriptor, size: bodyFont.pointSize)
        let fullRange = NSRange(location: 0, length: text.length)
        for match in regex.matches(in: text.string, range: fullRange) {
            text.addAttribute(.font, value: speakerFont, range: match.range)
            text.addAttribute(.foregroundColor, value: ReadingPalette.secondaryText, range: match.range)
        }
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

        /// 目标词下方的马克笔涂抹，画在正文之下，和标题荧光同一套笔触。
        private let markerLayer = CAShapeLayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            configureTextView()
            configureActionButtons()
            observeAppearanceChanges()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            configureTextView()
            configureActionButtons()
            observeAppearanceChanges()
        }

        /// 同步两枚行尾按钮的共享展示状态，保证与收藏页使用相同文案、图标和选中规则。
        func setActionPresentations(
            translation: ReadingSupplementActionPresentation,
            analysis: ReadingSupplementActionPresentation
        ) {
            apply(translation, to: translationButton)
            apply(analysis, to: analysisButton)
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
            markerLayer.contentsScale = UIScreen.main.scale
            layer.insertSublayer(markerLayer, at: 0)
            textView.isEditable = false
            textView.isSelectable = true
            textView.isScrollEnabled = false
            textView.backgroundColor = .clear
            textView.textColor = ReadingPalette.primaryText
            textView.textContainerInset = .zero
            textView.textContainer.lineFragmentPadding = 0
            textView.adjustsFontForContentSizeCategory = true
            textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
            addSubview(textView)
        }

        /// 初始化真实按钮，由容器负责把它们摆到正文最后一行后面。
        private func configureActionButtons() {
            [translationButton, analysisButton].forEach { button in
                button.titleLabel?.adjustsFontForContentSizeCategory = true
                button.heightAnchor.constraint(
                    greaterThanOrEqualToConstant: ReadingSupplementActionMetrics.minimumTouchHeight
                ).isActive = true
            }

            translationButton.addTarget(self, action: #selector(didTapTranslate), for: .touchUpInside)
            analysisButton.addTarget(self, action: #selector(didTapAnalyze), for: .touchUpInside)

            actionStack.axis = .horizontal
            actionStack.alignment = .center
            actionStack.spacing = ReadingSupplementActionMetrics.groupSpacing
            actionStack.addArrangedSubview(translationButton)
            actionStack.addArrangedSubview(analysisButton)
            addSubview(actionStack)
        }

        /// 把共享展示模型转换成 UIKit 配置，视觉数值与收藏页 SwiftUI 按钮保持一致。
        private func apply(_ presentation: ReadingSupplementActionPresentation, to button: UIButton) {
            let foregroundColor = presentation.isActive
                ? ReadingPalette.accentForeground
                : ReadingPalette.accent
            let backgroundColor = presentation.isActive
                ? ReadingPalette.accent
                : ReadingPalette.controlFill
            let borderColor = ReadingPalette.accent.withAlphaComponent(presentation.isActive ? 0.52 : 0.24)
            let actionFont = UIFontMetrics(forTextStyle: .footnote).scaledFont(
                for: UIFont.systemFont(
                    ofSize: ReadingSupplementActionMetrics.fontPointSize,
                    weight: .semibold
                )
            )
            let backgroundVerticalInset = ReadingSupplementActionMetrics.backgroundVerticalInset(
                for: actionFont.lineHeight
            )

            var configuration = UIButton.Configuration.plain()
            configuration.title = presentation.title
            configuration.image = presentation.isLoading ? nil : UIImage(systemName: presentation.systemImage)
            configuration.showsActivityIndicator = presentation.isLoading
            configuration.imagePadding = ReadingSupplementActionMetrics.contentSpacing
            configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
                pointSize: ReadingSupplementActionMetrics.iconPointSize,
                weight: .semibold
            )
            configuration.contentInsets = NSDirectionalEdgeInsets(
                top: ReadingSupplementActionMetrics.verticalPadding,
                leading: ReadingSupplementActionMetrics.horizontalPadding,
                bottom: ReadingSupplementActionMetrics.verticalPadding,
                trailing: ReadingSupplementActionMetrics.horizontalPadding
            )
            configuration.cornerStyle = .capsule
            configuration.baseForegroundColor = foregroundColor
            configuration.background.backgroundColor = backgroundColor
            configuration.background.strokeColor = borderColor
            configuration.background.strokeWidth = ReadingSupplementActionMetrics.borderWidth
            configuration.background.backgroundInsets = NSDirectionalEdgeInsets(
                top: backgroundVerticalInset,
                leading: 0,
                bottom: backgroundVerticalInset,
                trailing: 0
            )
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = actionFont
                return outgoing
            }
            button.configuration = configuration
            button.isEnabled = !presentation.isDisabled
            button.alpha = presentation.isDisabled && !presentation.isLoading ? 0.45 : 1
            button.accessibilityLabel = presentation.accessibilityLabel
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
            let actionLayout = prepareActionStack(for: width)
            let actionSize = actionLayout.size
            let line = lastLineLayout(width: width, textHeight: textHeight)
            let horizontalGap: CGFloat = 6
            let verticalGap: CGFloat = 2

            var actionX = line.endX + horizontalGap
            var actionY = line.rect.midY - actionSize.height / 2

            if actionLayout.usesVerticalAxis || actionX + actionSize.width > width {
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

        /// 辅助字号或窄正文下改为纵向按钮组，保证两枚操作按钮不会互相挤压或越界。
        private func prepareActionStack(for width: CGFloat) -> (size: CGSize, usesVerticalAxis: Bool) {
            let usesAccessibilitySize = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
            actionStack.axis = usesAccessibilitySize ? .vertical : .horizontal
            actionStack.alignment = usesAccessibilitySize ? .leading : .center

            var actionSize = actionStack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            if !usesAccessibilitySize, actionSize.width > width {
                actionStack.axis = .vertical
                actionStack.alignment = .leading
                actionSize = actionStack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
                return (actionSize, true)
            }

            return (actionSize, usesAccessibilitySize)
        }

        private func applyLayout(for width: CGFloat) {
            guard width > 0 else { return }
            let layout = measuredLayout(for: width)
            textView.frame = CGRect(x: 0, y: 0, width: width, height: layout.textHeight)
            actionStack.frame = layout.actionFrame
            updateVocabularyMarkers()
        }

        private func observeAppearanceChanges() {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (container: Self, _) in
                container.setNeedsLayout()
            }
        }

        /// 按目标词链接逐行取字形区域，在字的下半部画一笔马克笔；换行的词组每行各画一笔。
        private func updateVocabularyMarkers() {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            defer { CATransaction.commit() }

            markerLayer.frame = textView.frame
            guard let text = textView.attributedText, text.length > 0 else {
                markerLayer.path = nil
                return
            }

            let layoutManager = textView.layoutManager
            let textContainer = textView.textContainer
            let path = CGMutablePath()
            let noSelection = NSRange(location: NSNotFound, length: 0)

            text.enumerateAttribute(.link, in: NSRange(location: 0, length: text.length)) { value, range, _ in
                let url = (value as? URL) ?? (value as? String).flatMap(URL.init(string:))
                guard url?.scheme == "word" else { return }

                let font = text.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont
                    ?? UIFont.preferredFont(forTextStyle: .body)
                let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                var lineIndex: UInt64 = 0

                layoutManager.enumerateEnclosingRects(
                    forGlyphRange: glyphRange,
                    withinSelectedGlyphRange: noSelection,
                    in: textContainer
                ) { rect, _ in
                    guard rect.width > 1 else { return }
                    let baseline = rect.minY + font.ascender
                    let band = CGRect(
                        x: rect.minX - 1.5,
                        y: baseline - font.xHeight * 0.5,
                        width: rect.width + 3,
                        height: font.xHeight * 0.5 + abs(font.descender) * 0.7
                    )
                    let seed = UInt64(range.location) &* 0x9E37_79B9 &+ lineIndex
                    path.addPath(MarkerSwipeShape(seed: seed).path(in: band).cgPath)
                    lineIndex += 1
                }
            }

            let isDark = traitCollection.userInterfaceStyle == .dark
            markerLayer.path = path
            markerLayer.fillColor = ReadingPalette.marker
                .resolvedColor(with: traitCollection)
                .withAlphaComponent(isDark ? 0.36 : 0.55)
                .cgColor
            markerLayer.compositingFilter = isDark ? nil : "multiplyBlendMode"
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
        var onTranslateSelection: (String) -> Void

        init(
            onOpenURL: @escaping (URL) -> Void,
            onBookmarkSelection: @escaping (String) -> Void,
            onTranslateSelection: @escaping (String) -> Void
        ) {
            self.onOpenURL = onOpenURL
            self.onBookmarkSelection = onBookmarkSelection
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

            // 系统“翻译”由 UIKit 自己弹出，和点击高亮词的查词面板不一致；
            // 换成同名动作，两条入口统一走 WordLookupSheet。
            let translateAction = UIAction(title: "翻译", image: UIImage(systemName: "translate")) { [onTranslateSelection] _ in
                onTranslateSelection(selectedText)
            }
            let elements = Self.replacingSystemTranslate(in: suggestedActions, with: translateAction)
            return UIMenu(children: prioritizedMenuElements(from: elements, bookmarkAction: bookmarkAction))
        }

        /// 递归替换系统翻译命令（`_translate:`），其余系统菜单项保持原样。
        static func replacingSystemTranslate(in elements: [UIMenuElement], with action: UIAction) -> [UIMenuElement] {
            let systemTranslate = NSSelectorFromString("_translate:")
            return elements.map { element in
                if let command = element as? UICommand, command.action == systemTranslate {
                    let replacement = action.copy() as? UIAction ?? action
                    replacement.title = command.title
                    return replacement
                }
                if let menu = element as? UIMenu {
                    return menu.replacingChildren(replacingSystemTranslate(in: menu.children, with: action))
                }
                return element
            }
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
