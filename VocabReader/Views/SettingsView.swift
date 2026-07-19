import SwiftUI

/// 设置页的一级面板共用同一套信息结构，避免标题、说明和图标各自散落在视图里。
enum SettingsPanel: CaseIterable {
    case appearance
    case article
    case maiMemo
    case languageModel

    var title: String {
        switch self {
        case .appearance:
            return "外观主题"
        case .article:
            return "文章设置"
        case .maiMemo:
            return "墨墨词库"
        case .languageModel:
            return "文章生成模型"
        }
    }

    var subtitle: String {
        switch self {
        case .appearance:
            return "选择适合当前环境的阅读明暗模式"
        case .article:
            return "决定每天阅读的内容范围和文章结构"
        case .maiMemo:
            return "同步今日需要学习的单词"
        case .languageModel:
            return "用于生成文章、翻译和语言解析"
        }
    }

    var systemImage: String {
        switch self {
        case .appearance:
            return "circle.lefthalf.filled"
        case .article:
            return "text.book.closed"
        case .maiMemo:
            return "books.vertical"
        case .languageModel:
            return "sparkles"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    var onSave: (() -> Void)?
    private let showsCancelButton: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var draft: SettingsDraft
    @State private var initialAppearance: AppAppearance
    @State private var didSave = false
    @StateObject private var diagnosticsViewModel = SettingsConnectionDiagnosticsViewModel()

    /// 使用设置快照编辑，只有点击保存后才写回全局设置。
    init(
        settings: SettingsStore,
        showsCancelButton: Bool = true,
        onSave: (() -> Void)? = nil
    ) {
        self.settings = settings
        self.showsCancelButton = showsCancelButton
        self.onSave = onSave
        _draft = State(initialValue: settings.makeDraft())
        _initialAppearance = State(initialValue: settings.appearance)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinedPaperBackground()

                ScrollView {
                    LazyVStack(spacing: 18) {
                        SettingsPanelCard(panel: .appearance) {
                            appearanceSettingsContent
                        }

                        SettingsPanelCard(panel: .article) {
                            articleSettingsContent
                        }

                        SettingsPanelCard(panel: .maiMemo) {
                            maiMemoSettingsContent
                        }

                        SettingsPanelCard(panel: .languageModel) {
                            languageModelSettingsContent
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 36)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .tint(Color.readingTitle)
            .toolbar {
                if showsCancelButton {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消", action: cancelAndDismiss)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: saveAndDismiss)
                        .fontWeight(.semibold)
                        .disabled(!draft.isConfigured)
                }
            }
        }
        .onDisappear(perform: restoreAppearanceIfNeeded)
    }

    @ViewBuilder
    private var appearanceSettingsContent: some View {
        SettingsFieldLabel("显示模式")

        LazyVGrid(columns: SettingsLayout.choiceColumns(for: dynamicTypeSize), spacing: 8) {
            ForEach(AppAppearance.allCases) { appearance in
                SettingsChoiceButton(
                    title: appearance.title,
                    systemImage: appearance.systemImage,
                    isSelected: draft.appearance == appearance
                ) {
                    previewAppearance(appearance)
                }
            }
        }

        SettingsHint(appearanceHint)
    }

    /// 明确说明“跟随系统”的当前结果，以及手动选择对设备设置的覆盖关系。
    private var appearanceHint: String {
        guard draft.appearance == .system else {
            return "已优先使用\(draft.appearance.title)主题，不受设备外观变化影响"
        }

        let currentAppearance = colorScheme == .dark ? "深色" : "浅色"
        return "默认跟随系统；当前显示：\(currentAppearance)"
    }

    @ViewBuilder
    private var articleSettingsContent: some View {
        SettingsFieldLabel("文章主题")

        LazyVGrid(columns: SettingsLayout.choiceColumns(for: dynamicTypeSize), spacing: 8) {
            ForEach(ArticleTopic.allCases) { topic in
                SettingsChoiceButton(
                    title: topic.rawValue,
                    systemImage: topic.systemImageName,
                    isSelected: draft.selectedTopic == topic
                ) {
                    draft.selectedTopic = topic
                }
            }
        }

        SettingsFieldLabel("文章体裁")

        LazyVGrid(columns: SettingsLayout.choiceColumns(for: dynamicTypeSize), spacing: 8) {
            ForEach(ArticleScene.allCases) { scene in
                SettingsChoiceButton(
                    title: scene.rawValue,
                    systemImage: scene.systemImageName,
                    isSelected: draft.isSceneEnabled(scene)
                ) {
                    draft.setSceneEnabled(!draft.isSceneEnabled(scene), for: scene)
                }
            }
        }

        SettingsHint("至少保留一种体裁，生成时会在已选体裁中轮换")

        SettingsDivider()

        VStack(spacing: 0) {
            EditableStepper(
                title: "今日单词",
                subtitle: "当天计划覆盖的总词量",
                value: $draft.articleWordCount,
                range: ArticleGenerationLimits.articleWordCountRange,
                step: ArticleGenerationLimits.articleWordCountStep
            )

            SettingsDivider()

            EditableStepper(
                title: "每篇目标词汇",
                subtitle: "单篇文章需要自然包含的词量",
                value: $draft.wordsPerArticle,
                range: ArticleGenerationLimits.wordsPerArticleRange,
                step: ArticleGenerationLimits.wordsPerArticleStep
            )
        }
    }

    @ViewBuilder
    private var maiMemoSettingsContent: some View {
        SettingsTextField(
            label: "墨墨 Token",
            text: $draft.maiMemoToken,
            placeholder: "输入墨墨开放 API Token",
            isSecure: true
        )

        SettingsHint("获取路径：墨墨 App → 我的 → 更多设置 → 开放 API")

        SettingsConnectionStatus(
            isEnabled: !draft.maiMemoToken.isEmpty,
            status: diagnosticsViewModel.maiMemoStatus
        ) {
            Task {
                await diagnosticsViewModel.testMaiMemoConnection(
                    using: MaiMemoService(token: draft.maiMemoToken)
                )
            }
        }
    }

    @ViewBuilder
    private var languageModelSettingsContent: some View {
        SettingsTextField(
            label: "LLM Base URL",
            text: $draft.llmBaseURL,
            placeholder: "https://api.deepseek.com",
            keyboardType: .URL
        )

        SettingsTextField(
            label: "LLM API Key",
            text: $draft.llmAPIKey,
            placeholder: "输入模型服务 API Key",
            isSecure: true
        )

        SettingsTextField(
            label: "模型",
            text: $draft.llmModel,
            placeholder: "deepseek-v4-flash"
        )

        SettingsConnectionStatus(
            isEnabled: !(draft.llmAPIKey.isEmpty || draft.llmBaseURL.isEmpty || draft.llmModel.isEmpty),
            status: diagnosticsViewModel.llmStatus
        ) {
            Task {
                await diagnosticsViewModel.testLLMConnection(
                    using: LLMService(config: draft.llmConfig)
                )
            }
        }
    }

    /// 保存草稿后通知首页同步分页配置，并关闭设置页。
    private func saveAndDismiss() {
        didSave = true
        settings.apply(draft)
        settings.save()
        onSave?()
        dismiss()
    }

    /// 临时更新全局外观以驱动窗口即时预览，真正的持久化仍由“保存”完成。
    private func previewAppearance(_ appearance: AppAppearance) {
        draft.appearance = appearance
        settings.appearance = appearance
    }

    /// 取消时回滚预览，保证其他设置仍保持草稿式编辑语义。
    private func cancelAndDismiss() {
        draft.appearance = initialAppearance
        settings.appearance = initialAppearance
        dismiss()
    }

    /// 下滑关闭设置页时同样回滚未保存预览，避免临时主题残留到主界面。
    private func restoreAppearanceIfNeeded() {
        guard !didSave else { return }
        settings.appearance = initialAppearance
    }
}

// MARK: - Settings layout

private enum SettingsLayout {
    /// 普通字号保持紧凑三列；辅助字号改为单列，避免主题和文章选项被截断。
    static func choiceColumns(for dynamicTypeSize: DynamicTypeSize) -> [GridItem] {
        let columnCount = dynamicTypeSize.isAccessibilitySize ? 1 : 3
        return Array(
            repeating: GridItem(.flexible(), spacing: 8),
            count: columnCount
        )
    }
}
