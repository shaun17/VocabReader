import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    var onSave: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Token", text: $settings.maiMemoToken)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("墨墨 API Token")
                } footer: {
                    Link("如何获取 Token？",
                         destination: URL(string: "https://open.maimemo.com")!)
                        .font(.footnote)
                }

                Section("LLM 配置") {
                    TextField("Base URL（如 https://api.openai.com/v1）",
                              text: $settings.llmBaseURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    SecureField("API Key", text: $settings.llmAPIKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    TextField("模型名称（如 gpt-4o）", text: $settings.llmModel)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        settings.save()
                        onSave?()
                        dismiss()
                    }
                    .disabled(!settings.isConfigured)
                }
            }
        }
    }
}
