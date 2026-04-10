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
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // MARK: - 文章设置
                    SettingsSectionHeader(title: "文章设置")

                    SettingsLabel("文章主题")
                    SettingsRow {
                        Picker("主题", selection: $draft.selectedTopic) {
                            ForEach(ArticleTopic.allCases) { topic in
                                Text(topic.rawValue).tag(topic)
                            }
                        }
                        .tint(.secondary)
                    }

                    SettingsLabel("文章体裁")
                    ForEach(ArticleScene.allCases) { scene in
                        SettingsRow {
                            Toggle(scene.rawValue, isOn: sceneEnabledBinding(for: scene))
                                .tint(Color.readingTitle)
                        }
                    }

                    SettingsHint("至少启用一种体裁")

                    SettingsRow {
                        EditableStepper(
                            title: "今日单词",
                            value: $draft.articleWordCount,
                            range: 10...100,
                            step: 10
                        )
                    }

                    SettingsRow {
                        EditableStepper(
                            title: "每篇词汇",
                            value: $draft.wordsPerArticle,
                            range: 5...30,
                            step: 5
                        )
                    }

                    // MARK: - 连接
                    SettingsSectionHeader(title: "连接")

                    SettingsRow {
                        UnderlinedTextField(
                            label: "墨墨 Token",
                            text: $draft.maiMemoToken,
                            isSecure: true
                        )
                    }

                    SettingsHint("获取路径：墨墨 App \u{2192}「我的」\u{2192}「更多设置」\u{2192}「开放 API」复制 Token")

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

                    SettingsRow {
                        UnderlinedTextField(
                            label: "Base URL",
                            text: $draft.llmBaseURL,
                            placeholder: "https://api.openai.com/v1",
                            keyboardType: .URL
                        )
                    }

                    SettingsRow {
                        UnderlinedTextField(
                            label: "API Key",
                            text: $draft.llmAPIKey,
                            isSecure: true
                        )
                    }

                    SettingsRow {
                        UnderlinedTextField(
                            label: "模型",
                            text: $draft.llmModel,
                            placeholder: "gpt-4o"
                        )
                    }

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

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
            }
            .background(Color.readingBackground.ignoresSafeArea())
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
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

    private func sceneEnabledBinding(for scene: ArticleScene) -> Binding<Bool> {
        Binding(
            get: { draft.isSceneEnabled(scene) },
            set: { isEnabled in draft.setSceneEnabled(isEnabled, for: scene) }
        )
    }
}

// MARK: - Settings components

private struct SettingsSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(.subheadline, design: .serif))
            .foregroundStyle(Color.readingTitle)
            .padding(.top, 32)
            .padding(.bottom, 12)
    }
}

private struct SettingsLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 12)
    }
}

private struct SettingsRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.vertical, 10)
    }
}

private struct SettingsHint: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.top, 2)
            .padding(.bottom, 8)
    }
}

/// 带底部下划线的输入框，视觉上更明确。
private struct UnderlinedTextField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .font(.system(.body, design: .serif))
            .keyboardType(keyboardType)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .padding(.bottom, 6)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.readingRule)
                    .frame(height: 1)
            }
        }
    }
}

private struct SettingsConnectionStatus: View {
    let isEnabled: Bool
    let status: ConnectionTestStatus
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button {
                guard isEnabled else { return }
                action()
            } label: {
                Text("测试连接")
                    .font(.caption)
                    .foregroundColor(isEnabled ? Color.readingTitle : .gray.opacity(0.4))
            }
            .buttonStyle(.plain)

            Spacer()

            switch status {
            case .idle:
                EmptyView()
            case .testing:
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("测试中…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .success(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.green)
            case .failure(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 6)
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
                .font(.system(.body, design: .serif))
            Spacer()
            HStack(spacing: 0) {
                Button {
                    let newValue = max(value - step, range.lowerBound)
                    value = newValue
                    text = String(newValue)
                } label: {
                    Image(systemName: "minus")
                        .font(.caption)
                        .frame(width: 28, height: 28)
                        .foregroundColor(value <= range.lowerBound ? .gray.opacity(0.3) : Color.readingTitle)
                }
                .buttonStyle(.plain)
                .disabled(value <= range.lowerBound)

                TextField("", text: $text)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.system(.body, design: .serif))
                    .frame(width: 40)
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
                        .font(.caption)
                        .frame(width: 28, height: 28)
                        .foregroundColor(value >= range.upperBound ? .gray.opacity(0.3) : Color.readingTitle)
                }
                .buttonStyle(.plain)
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
