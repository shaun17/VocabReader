import SwiftUI

/// 一级设置面板统一使用阅读纸片底板和相同的标题层级。
struct SettingsPanelCard<Content: View>: View {
    let panel: SettingsPanel
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: panel.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.readingTitle)
                    .frame(width: 38, height: 38)
                    .background {
                        Circle()
                            .fill(Color.readingTitle.opacity(0.10))
                            .overlay {
                                Circle()
                                    .stroke(Color.readingTitle.opacity(0.16), lineWidth: 0.8)
                            }
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(panel.title)
                        .font(.system(.headline, design: .serif).weight(.semibold))
                        .foregroundStyle(Color.readingTextPrimary)

                    Text(panel.subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.readingTextSecondary)
                }
            }

            SettingsDivider()

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ReadingCardBackground()
        }
    }
}

struct SettingsFieldLabel: View {
    let text: String

    /// 字段标题只负责建立局部层级，不与卡片主标题竞争。
    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.readingTextSecondary)
    }
}

struct SettingsChoiceButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)

                Text(title)
                    .lineLimit(2)

                if isSelected {
                    Image(systemName: "checkmark")
                }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(isSelected ? Color.readingAccentForeground : Color.readingTitle)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background {
                Capsule(style: .continuous)
                    .fill(isSelected ? Color.readingTitle : Color.readingControlFill)
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(
                                Color.readingTitle.opacity(isSelected ? 0.72 : 0.24),
                                lineWidth: 0.8
                            )
                    }
            }
        }
        .buttonStyle(SettingsPressButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct SettingsHint: View {
    let text: String

    /// 提示文字统一使用信息图标和浅色纸面，避免游离在卡片中。
    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Label(text, systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(Color.readingTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.readingControlFill.opacity(0.72))
            }
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.readingSeparator.opacity(0.72))
            .frame(height: 1)
    }
}

/// 设置输入框统一使用纸面内嵌样式，URL、密钥和模型名不再表现为三条松散下划线。
struct SettingsTextField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SettingsFieldLabel(label)

            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .font(.system(.subheadline, design: .rounded))
            .foregroundStyle(Color.readingTextPrimary)
            .keyboardType(keyboardType)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.readingControlFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.readingRule.opacity(0.95), lineWidth: 0.8)
                    }
            }
        }
    }
}

struct SettingsConnectionStatus: View {
    let isEnabled: Bool
    let status: ConnectionTestStatus
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                guard isEnabled else { return }
                action()
            } label: {
                HStack(spacing: 7) {
                    if status == .testing {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(Color.readingAccentForeground)
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                    }

                    Text(status == .testing ? "测试中…" : "测试连接")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(buttonForegroundColor)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background {
                    Capsule(style: .continuous)
                        .fill(buttonBackgroundColor)
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(buttonBorderColor, lineWidth: 0.8)
                        }
                }
            }
            .buttonStyle(SettingsPressButtonStyle())
            .disabled(!isEnabled || status == .testing)

            statusMessage
        }
    }

    @ViewBuilder
    private var statusMessage: some View {
        switch status {
        case .idle, .testing:
            EmptyView()
        case .success(let message):
            Label(message, systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.readingSuccess)
        case .failure(let message):
            Label(message, systemImage: "exclamationmark.circle.fill")
                .font(.caption)
                .foregroundStyle(Color.readingError)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var buttonForegroundColor: Color {
        status == .testing ? .readingAccentForeground : (isEnabled ? .readingTitle : .readingTextSecondary)
    }

    private var buttonBackgroundColor: Color {
        status == .testing ? .readingTitle : .readingControlFill.opacity(isEnabled ? 1 : 0.48)
    }

    private var buttonBorderColor: Color {
        Color.readingTitle.opacity(isEnabled ? 0.26 : 0.10)
    }
}

struct SettingsPressButtonStyle: ButtonStyle {
    /// 所有自定义按钮共享轻微按压反馈，不引入与阅读页不一致的弹跳动画。
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.84 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
