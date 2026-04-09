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
                    Text("文章生成")
                } footer: {
                    Text("今日单词数量表示从墨墨查询今日已经完成记忆的单词数量。每篇文章词汇量表示生成单篇文章时使用的单词数量。")
                }

                Section {
                    SecureField("Token", text: $draft.maiMemoToken)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    HStack(spacing: 8) {
                        Text("墨墨 API Token")
                        Spacer(minLength: 0)
                        Link("如何获取 Token？",
                             destination: URL(string: "https://open.maimemo.com")!)
                            .font(.footnote)
                    }
                } footer: {
                    SettingsActionRow(
                        title: "测试",
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
                    Text("LLM")
                } footer: {
                    SettingsActionRow(
                        title: "测试",
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
