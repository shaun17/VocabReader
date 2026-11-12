import SwiftUI
import Translation

/// 阅读页的查词面板：一张从段落里抽出来的词卡。
///
/// 不用系统 `translationPresentation`：它要先自动识别语种，单个英文词经常识别失败，
/// 会先弹选语言面板、选完再换成另一种尺寸的译文面板，远程面板首次弹出也明显卡顿。
/// 这里固定 英文 → 简体中文：语言包已装时先用设备端翻译秒出释义和原句译文，
/// 同时用 LLM 补全音标、文中释义说明、常见词义和搭配。
struct WordLookupSheet: View {
    @StateObject private var viewModel: WordLookupViewModel
    @ObservedObject private var bookmarkStore = BookmarkStore.shared
    @State private var translationConfiguration: TranslationSession.Configuration?
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    /// 文章朗读是否在进行（含暂停）；进行中时单词发音结束不交还音频会话。
    private let isArticleAudioActive: () -> Bool

    init(
        request: WordLookupRequest,
        service: WordLookupServiceProtocol,
        isArticleAudioActive: @escaping () -> Bool = { false }
    ) {
        _viewModel = StateObject(wrappedValue: WordLookupViewModel(request: request, service: service))
        self.isArticleAudioActive = isArticleAudioActive
    }

    private var request: WordLookupRequest { viewModel.request }
    private var seed: UInt64 { SketchSeed.make(request.text.lowercased()) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                SketchDivider(seed: seed &+ 1)

                contextMeaningSection

                if !request.sentence.isEmpty {
                    sentenceSection
                }

                if let result = viewModel.result {
                    if !result.senses.isEmpty {
                        sensesSection(result.senses)
                    }
                    if !result.collocations.isEmpty {
                        collocationsSection(result.collocations)
                    }
                } else if viewModel.isLoading {
                    sensesPlaceholder
                }

                if let message = viewModel.failureMessage {
                    failureRow(message)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 24)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
            .animation(accessibilityReduceMotion ? nil : .easeInOut(duration: 0.25), value: viewModel.detail)
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationSizing(.form)
        .presentationBackground(Color.readingBackground)
        .task { await viewModel.load() }
        .task { await prepareOnDeviceTranslation() }
        .translationTask(translationConfiguration) { session in
            await translateOnDevice(using: session)
        }
        .onDisappear { viewModel.stopSpeaking() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text(request.text)
                    .font(.system(.largeTitle, design: .serif).italic().weight(.semibold))
                    .foregroundStyle(Color.readingTitle)
                    .markerHighlight(seed: seed)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                    .textSelection(.enabled)

                metaLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                RoundIconButton(
                    systemImage: viewModel.isSpeaking ? "speaker.wave.2.fill" : "speaker.wave.2",
                    isActive: viewModel.isSpeaking,
                    accessibilityLabel: viewModel.isSpeaking ? "停止发音" : "发音"
                ) {
                    viewModel.pronounce(keepsAudioSession: isArticleAudioActive())
                }
                .symbolEffect(.variableColor.iterative, isActive: viewModel.isSpeaking && !accessibilityReduceMotion)

                RoundIconButton(
                    systemImage: isBookmarked ? "star.fill" : "star",
                    isActive: isBookmarked,
                    accessibilityLabel: isBookmarked ? "取消收藏" : "收藏"
                ) {
                    toggleBookmark()
                }
                .sensoryFeedback(.success, trigger: isBookmarked) { _, newValue in newValue }
            }
            .padding(.top, 6)
        }
    }

    /// 音标 · 词性 · 今日词汇，各项缺省时自动收拢。
    @ViewBuilder
    private var metaLine: some View {
        let phonetic = viewModel.result?.phonetic ?? ""
        let partOfSpeech = viewModel.result?.partOfSpeech ?? ""

        if !phonetic.isEmpty || !partOfSpeech.isEmpty || request.isTargetWord || viewModel.isLoading {
            HStack(spacing: 8) {
                if !phonetic.isEmpty {
                    Text(phonetic)
                        .font(.system(.callout, design: .serif))
                        .foregroundStyle(Color.readingTextSecondary)
                } else if viewModel.isLoading {
                    Text("/ˈfəʊnəʊ/")
                        .font(.system(.callout, design: .serif))
                        .redacted(reason: .placeholder)
                }

                if !partOfSpeech.isEmpty {
                    TagLabel(text: partOfSpeech, style: .outline)
                }

                if request.isTargetWord {
                    TagLabel(text: "今日词汇", style: .marker)
                }
            }
        }
    }

    // MARK: - Sections

    private var contextMeaningSection: some View {
        LookupSection(title: "文中释义") {
            if let meaning = viewModel.contextMeaning {
                VStack(alignment: .leading, spacing: 6) {
                    Text(meaning)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.readingTextPrimary)
                        .textSelection(.enabled)

                    if let note = viewModel.result?.contextNote, !note.isEmpty {
                        Text(note)
                            .font(.subheadline)
                            .foregroundStyle(Color.readingTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else if viewModel.isLoading {
                VStack(alignment: .leading, spacing: 6) {
                    Text("正在查询释义")
                        .font(.title3.weight(.semibold))
                    Text("这里会说明它在这句话里的语气和用法")
                        .font(.subheadline)
                }
                .redacted(reason: .placeholder)
            } else {
                Text("暂无释义")
                    .font(.subheadline)
                    .foregroundStyle(Color.readingTextTertiary)
            }
        }
    }

    /// 原句像一张夹在词卡里的便签：英文里把这个词涂上荧光，下面跟中文译文。
    private var sentenceSection: some View {
        LookupSection(title: "原句") {
            VStack(alignment: .leading, spacing: 10) {
                Text(highlightedSentence)
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(Color.readingTextPrimary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                if let translation = viewModel.sentenceTranslation {
                    Text(translation)
                        .font(.subheadline)
                        .foregroundStyle(Color.readingTextSecondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                } else if viewModel.isLoading {
                    Text("这里会显示整句的中文翻译，帮助理解上下文")
                        .font(.subheadline)
                        .redacted(reason: .placeholder)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ReadingCardBackground(
                    seed: seed &+ 7,
                    fill: .readingCardFill,
                    cornerRadius: 12,
                    cornerVariance: 3,
                    lineOpacity: 0.7
                )
            }
        }
    }

    private func sensesSection(_ senses: [WordLookupResult.Sense]) -> some View {
        LookupSection(title: "常见词义") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(senses.prefix(3).enumerated()), id: \.offset) { _, sense in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(sense.partOfSpeech.isEmpty ? "·" : sense.partOfSpeech)
                            .font(.system(.footnote, design: .serif).italic())
                            .foregroundStyle(Color.readingTitle)
                            .frame(minWidth: 34, alignment: .leading)
                        Text(sense.meaning)
                            .font(.body)
                            .foregroundStyle(Color.readingTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func collocationsSection(_ collocations: [WordLookupResult.Collocation]) -> some View {
        LookupSection(title: "常用搭配") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(collocations.prefix(3).enumerated()), id: \.offset) { _, collocation in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(collocation.phrase)
                            .font(.system(.body, design: .serif).italic())
                            .foregroundStyle(Color.readingTextPrimary)
                        if !collocation.meaning.isEmpty {
                            Text(collocation.meaning)
                                .font(.footnote)
                                .foregroundStyle(Color.readingTextSecondary)
                        }
                    }
                }
            }
        }
    }

    private var sensesPlaceholder: some View {
        LookupSection(title: "常见词义") {
            VStack(alignment: .leading, spacing: 10) {
                Text("n.  常见含义一")
                Text("v.  常见含义二，稍长一些")
            }
            .font(.body)
            .redacted(reason: .placeholder)
        }
    }

    private func failureRow(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(viewModel.contextMeaning == nil ? message : "详细词条加载失败：\(message)")
                .font(.footnote)
                .foregroundStyle(Color.readingError)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("重试") {
                Task { await viewModel.load() }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.readingTitle)
        }
    }

    // MARK: - Helpers

    private var highlightedSentence: AttributedString {
        var attributed = AttributedString(request.sentence)
        if let range = attributed.range(of: request.text, options: .caseInsensitive) {
            attributed[range].backgroundColor = Color.readingMarker.opacity(0.5)
            attributed[range].foregroundColor = Color.readingTitle
        }
        return attributed
    }

    private var isBookmarked: Bool {
        bookmarkStore.bookmarks.contains { $0.spelling.caseInsensitiveCompare(request.text) == .orderedSame }
    }

    private func toggleBookmark() {
        let matches = bookmarkStore.bookmarks.filter {
            $0.spelling.caseInsensitiveCompare(request.text) == .orderedSame
        }
        if matches.isEmpty {
            bookmarkStore.add(spelling: request.text, sentence: request.sentence.isEmpty ? request.text : request.sentence)
        } else {
            matches.forEach { bookmarkStore.remove(id: $0.id) }
        }
    }

    // MARK: - On-device translation

    private static let source = Locale.Language(identifier: "en")
    private static let target = Locale.Language(identifier: "zh-Hans")

    /// 只有语言包已装好才启用设备端翻译：否则 translationTask 会再弹一层系统下载 / 不支持面板。
    private func prepareOnDeviceTranslation() async {
        let status = await LanguageAvailability().status(from: Self.source, to: Self.target)
        guard status == .installed else { return }
        translationConfiguration = TranslationSession.Configuration(source: Self.source, target: Self.target)
    }

    private func translateOnDevice(using session: TranslationSession) async {
        var requests = [TranslationSession.Request(sourceText: request.text, clientIdentifier: "word")]
        if !request.sentence.isEmpty {
            requests.append(TranslationSession.Request(sourceText: request.sentence, clientIdentifier: "sentence"))
        }
        guard let responses = try? await session.translations(from: requests) else { return }
        viewModel.applyQuickTranslation(
            meaning: responses.first { $0.clientIdentifier == "word" }?.targetText,
            sentence: responses.first { $0.clientIdentifier == "sentence" }?.targetText
        )
    }
}

// MARK: - Components

private struct LookupSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.readingTextTertiary)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TagLabel: View {
    enum Style { case outline, marker }

    let text: String
    let style: Style

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(style == .marker ? Color.readingTitle : Color.readingTextSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background {
                Capsule(style: .continuous)
                    .fill(style == .marker ? Color.readingMarker.opacity(0.35) : Color.clear)
                    .overlay {
                        if style == .outline {
                            Capsule(style: .continuous)
                                .stroke(Color.readingSketchLine.opacity(0.6), lineWidth: 0.8)
                        }
                    }
            }
    }
}

private struct RoundIconButton: View {
    let systemImage: String
    let isActive: Bool
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.readingTitle)
                .frame(width: 44, height: 44)
                .background {
                    Circle()
                        .fill(isActive ? Color.readingMarker.opacity(0.35) : Color.readingControlFill)
                        .overlay {
                            Circle().stroke(Color.readingSketchLine.opacity(0.5), lineWidth: 0.8)
                        }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
