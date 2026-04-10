import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    var onSave: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SettingsDraft
    @StateObject private var diagnosticsViewModel = SettingsConnectionDiagnosticsViewModel()

    init(settings: SettingsStore, onSave: (() -> Void)? = nil) {
        self.settings = settings
        self.onSave = onSave
        _draft = State(initialValue: settings.makeDraft())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("文章主题", selection: $draft.selectedTopic) {
                        ForEach(ArticleTopic.allCases) { topic in
                            Text(topic.rawValue).tag(topic)
                        }
                    }
                } header: {
                    Label("主题", systemImage: "text.book.closed")
                }

                Section {
                    ForEach(ArticleScene.allCases) { scene in
                        Toggle(scene.rawValue, isOn: sceneEnabledBinding(for: scene))
                    }
                } header: {
                    Label("体裁", systemImage: "doc.richtext")
                } footer: {
                    Text("至少启用一种体裁")
                }

                Section {
                    EditableStepper(
                        title: "今日单词数量",
                        value: $draft.articleWordCount,
                        range: 10...100,
                        step: 10
                    )

                    EditableStepper(
                        title: "每篇文章词汇量",
                        value: $draft.wordsPerArticle,
                        range: 5...30,
                        step: 5
                    )
                } header: {
                    Label("词汇量", systemImage: "textformat.abc")
                } footer: {
                    Text("今日单词数量从墨墨查询已完成记忆的单词。每篇文章词汇量控制单篇使用的单词数。")
                }

                Section {
                    SecureField("Token", text: $draft.maiMemoToken)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Label("墨墨背单词", systemImage: "key")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("获取路径：墨墨 App →「我的」→「更多设置」→「开放 API」复制 Token")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        SettingsActionRow(
                            title: "测试连接",
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
                }

                Section {
                    TextField("Base URL（如 https://api.openai.com/v1）",
                              text: $draft.llmBaseURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    SecureField("API Key", text: $draft.llmAPIKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    TextField("模型名称（如 gpt-4o）", text: $draft.llmModel)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Label("AI 模型", systemImage: "cpu")
                } footer: {
                    SettingsActionRow(
                        title: "测试连接",
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
            }
            .scrollContentBackground(.hidden)
            .background(Color.readingBackground)
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        settings.apply(draft)
                        settings.save()
                        onSave?()
                        dismiss()
                    }
                    .disabled(!draft.isConfigured)
                }
            }
        }
    }

    /// 为体裁开关提供双向绑定，并保证始终至少保留一个启用体裁。
    private func sceneEnabledBinding(for scene: ArticleScene) -> Binding<Bool> {
        Binding(
            get: {
                draft.isSceneEnabled(scene)
            },
            set: { isEnabled in
                draft.setSceneEnabled(isEnabled, for: scene)
            }
        )
    }
}

private struct EditableStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(title: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int) {
        self.title = title
        _value = value
        self.range = range
        self.step = step
        _text = State(initialValue: String(value.wrappedValue))
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            HStack(spacing: 0) {
                Button {
                    let newValue = max(value - step, range.lowerBound)
                    value = newValue
                    text = String(newValue)
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.borderless)
                .disabled(value <= range.lowerBound)

                TextField("", text: $text)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 44)
                    .focused($isFocused)
                    .onChange(of: isFocused) { _, focused in
                        if !focused { commitText() }
                    }
                    .onSubmit { commitText() }

                Button {
                    let newValue = min(value + step, range.upperBound)
                    value = newValue
                    text = String(newValue)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.borderless)
                .disabled(value >= range.upperBound)
            }
        }
    }

    private func commitText() {
        guard let parsed = Int(text) else {
            text = String(value)
            return
        }
        let clamped = min(max(parsed, range.lowerBound), range.upperBound)
        let snapped = range.lowerBound + ((clamped - range.lowerBound + step / 2) / step) * step
        let final = min(snapped, range.upperBound)
        value = final
        text = String(final)
    }
}

private struct SettingsActionRow: View {
    let title: String
    let isEnabled: Bool
    let status: ConnectionTestStatus
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ActionLinkText(title: title, isEnabled: isEnabled, action: action)
            Spacer(minLength: 12)
            ConnectionStatusRow(status: status)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }
}

private struct ActionLinkText: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Text(title)
            .font(.footnote)
            .foregroundStyle(isEnabled ? .blue : .secondary)
            .contentShape(Rectangle())
            .onTapGesture {
                guard isEnabled else { return }
                action()
            }
    }
}

private struct ConnectionStatusRow: View {
    let status: ConnectionTestStatus

    var body: some View {
        switch status {
        case .idle:
            EmptyView()
        case .testing:
            HStack(spacing: 8) {
                ProgressView()
                Text("测试中…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        case .success(let message):
            Text(message)
                .font(.footnote)
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity, alignment: .trailing)
        case .failure(let message):
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
