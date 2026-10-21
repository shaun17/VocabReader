import SwiftUI

/// 设置页的一级面板共用同一套信息结构，避免标题、说明和图标各自散落在视图里。
enum SettingsPanel: CaseIterable {
    case appearance
    case article
    case speech
    case maiMemo
    case languageModel

    var title: String {
        switch self {
        case .appearance:
            return "外观主题"
        case .article:
            return "文章设置"
        case .speech:
            return "朗读语音"
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
        case .speech:
            return "选择文章朗读使用的语音引擎"
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
        case .speech:
            return "waveform"
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
    @State private var draft: SettingsDraft
    @State private var initialAppearance: AppAppearance
    @State private var didSave = false
    @StateObject private var diagnosticsViewModel = SettingsConnectionDiagnosticsViewModel()
    @ObservedObject private var phononEngine = PhononEngine.shared

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
                    LazyVStack(spacing: 14) {
                        SettingsPanelCard(panel: .appearance) {
                            appearanceSettingsContent
                        }

                        SettingsPanelCard(panel: .article) {
                            articleSettingsContent
                        }

                        SettingsPanelCard(panel: .speech) {
                            speechSettingsContent
                        }

                        SettingsPanelCard(panel: .maiMemo) {
                            maiMemoSettingsContent
                        }

                        SettingsPanelCard(panel: .languageModel) {
                            languageModelSettingsContent
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
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
        .onDisappear {
            restoreAppearanceIfNeeded()
            phononEngine.stopPreview()
        }
    }

    @ViewBuilder
    private var appearanceSettingsContent: some View {
        SettingsFieldLabel("显示模式")

        SettingsChoiceFlowLayout(horizontalSpacing: 6, verticalSpacing: 0) {
            ForEach(AppAppearance.allCases) { appearance in
                SettingsChoiceButton(
                    title: appearance.title,
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

        SettingsChoiceFlowLayout(horizontalSpacing: 6, verticalSpacing: 0) {
            ForEach(ArticleTopic.allCases) { topic in
                SettingsChoiceButton(
                    title: topic.rawValue,
                    isSelected: draft.selectedTopic == topic
                ) {
                    draft.selectedTopic = topic
                }
            }
        }

        SettingsFieldLabel("文章体裁")

        SettingsChoiceFlowLayout(horizontalSpacing: 6, verticalSpacing: 0) {
            ForEach(ArticleScene.allCases) { scene in
                SettingsChoiceButton(
                    title: scene.rawValue,
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
    private var speechSettingsContent: some View {
        SettingsFieldLabel("语音引擎")

        SettingsChoiceFlowLayout(horizontalSpacing: 6, verticalSpacing: 0) {
            ForEach(availableSpeechEngines) { engine in
                SettingsChoiceButton(
                    title: engine.title,
                    isSelected: draft.speechEngine == engine
                ) {
                    selectSpeechEngine(engine)
                }
            }
        }

        if draft.speechEngine == .phonon {
            phononModelStatus
        }

        // 模型下载并编译完成前音色无法试听也用不上，先不展示，避免和下载、编译提示挤在一起。
        if draft.speechEngine == .phonon, phononEngine.status == .ready {
            SettingsDivider()

            NavigationLink {
                PhononVoicePickerView(selection: $draft.phononVoice, engine: phononEngine)
            } label: {
                SettingsNavigationRow(
                    title: "音色",
                    subtitle: selectedPhononVoice.detail,
                    value: selectedPhononVoice.name
                )
            }
            .buttonStyle(SettingsPressButtonStyle())
        }
    }

    /// 当前包拿不到模型时不展示 Phonon，避免用户选中后只能看到失败提示。
    private var availableSpeechEngines: [SpeechEngine] {
        SpeechEngine.allCases.filter { engine in
            engine != .phonon || phononEngine.isAvailable || draft.speechEngine == .phonon
        }
    }

    /// 选中 Phonon 时立即尝试加载本机已有模型，这样未下载的状态能马上反映到按钮上。
    private func selectSpeechEngine(_ engine: SpeechEngine) {
        draft.speechEngine = engine
        guard engine == .phonon else { return }
        Task { await phononEngine.prepare() }
    }

    /// 模型需要用户主动下载，加载、编译和失败回退都在这里说明。
    @ViewBuilder
    private var phononModelStatus: some View {
        switch phononEngine.status {
        case .idle, .preparing:
            SettingsHint(phononPreparingMessage)
        case .notDownloaded:
            phononDownloadButton(title: "下载模型（\(PhononEngine.downloadSizeDescription)）")
            SettingsHint("建议在 Wi-Fi 下下载；下载完成前朗读使用系统语音")
        case .downloading(let fraction):
            ProgressView(value: fraction)
                .tint(Color.readingTitle)
            SettingsHint("正在下载模型 \(Int(fraction * 100))%，请保持 App 在前台")
        case .ready:
            EmptyView()
        case .failed(let message):
            phononDownloadButton(title: "重试")
            SettingsHint("加载失败，朗读将使用系统语音：\(message)")
        }
    }

    private var selectedPhononVoice: PhononVoice {
        PhononVoice.named(draft.phononVoice) ?? PhononVoice.catalog[0]
    }

    private var phononPreparingMessage: String {
        if case .preparing(let message) = phononEngine.status {
            return message
        }
        return "正在检查本机模型…"
    }

    private func phononDownloadButton(title: String) -> some View {
        SettingsCapsuleButton(
            title: title,
            busyTitle: "准备中…",
            systemImage: "arrow.down.circle",
            isEnabled: PhononEngine.remoteBaseURL != nil
        ) {
            Task { await phononEngine.prepare(allowDownload: true) }
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
