import Foundation

enum ArticleParagraphExpansionPanel: Equatable {
    case translation
    case analysis
}

@MainActor
final class ArticleParagraphTranslationViewModel: ObservableObject {
    @Published var translation: String?
    @Published var analysis: String?
    @Published var expandedPanel: ArticleParagraphExpansionPanel?
    @Published var loadingPanel: ArticleParagraphExpansionPanel?
    @Published var error: String?

    private let paragraph: String
    private let translator: ArticleParagraphTranslatorProtocol

    init(paragraph: String, translator: ArticleParagraphTranslatorProtocol) {
        self.paragraph = paragraph
        self.translator = translator
    }

    var isExpanded: Bool {
        expandedPanel != nil
    }

    var isLoading: Bool {
        loadingPanel != nil
    }

    /// 处理“翻译”入口：已加载时只切换展开状态，未加载时请求段落译文。
    func didTapTranslateButton() async {
        await toggleOrLoad(panel: .translation) {
            translation = try await translator.translate(paragraph: paragraph)
        }
    }

    /// 处理“解析”入口：解释语法、表达和俚语，不复用翻译结果。
    func didTapAnalyzeButton() async {
        await toggleOrLoad(panel: .analysis) {
            analysis = try await translator.analyze(paragraph: paragraph)
        }
    }

    /// 统一管理翻译和解析的加载、缓存、展开与错误状态。
    private func toggleOrLoad(
        panel: ArticleParagraphExpansionPanel,
        load: () async throws -> Void
    ) async {
        guard loadingPanel == nil else { return }

        if hasLoadedContent(for: panel) {
            expandedPanel = expandedPanel == panel ? nil : panel
            error = nil
            return
        }

        loadingPanel = panel
        expandedPanel = nil
        error = nil

        do {
            try await load()
            expandedPanel = panel
        } catch {
            self.error = error.localizedDescription
            expandedPanel = nil
        }

        loadingPanel = nil
    }

    /// 判断对应面板是否已有缓存内容，避免重复请求 LLM。
    private func hasLoadedContent(for panel: ArticleParagraphExpansionPanel) -> Bool {
        switch panel {
        case .translation:
            return translation != nil
        case .analysis:
            return analysis != nil
        }
    }
}
