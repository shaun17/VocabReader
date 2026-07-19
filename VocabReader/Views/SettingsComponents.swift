import SwiftUI

/// 一级设置面板统一使用阅读纸片底板和相同的标题层级。
struct SettingsPanelCard<Content: View>: View {
    let panel: SettingsPanel
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: panel.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.readingTitle)
                    .frame(width: 18, alignment: .leading)
                    .padding(.top, 3)

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
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.readingCardFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.readingSeparator.opacity(0.72), lineWidth: 0.8)
                }
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

/// 设置选项把紧凑视觉壳与完整触控区域分离，避免三列网格再次出现大块胶囊。
enum SettingsChoiceButtonMetrics {
    static let visualHeight: CGFloat = 34
    static let minimumTouchHeight: CGFloat = 44
    static let horizontalPadding: CGFloat = 9
    static let contentSpacing: CGFloat = 4
    static let cornerRadius: CGFloat = 10
    static let borderWidth: CGFloat = 0.75
}

struct SettingsChoiceButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SettingsChoiceButtonMetrics.contentSpacing) {
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.readingTitle)
                    .frame(width: 10)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.readingTextPrimary)
                .padding(.horizontal, SettingsChoiceButtonMetrics.horizontalPadding)
                .frame(minHeight: SettingsChoiceButtonMetrics.visualHeight)
                .background {
                    RoundedRectangle(
                        cornerRadius: SettingsChoiceButtonMetrics.cornerRadius,
                        style: .continuous
                    )
                        .fill(
                            isSelected
                                ? Color.readingTitle.opacity(0.14)
                                : Color.readingControlFill
                        )
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: SettingsChoiceButtonMetrics.cornerRadius,
                                style: .continuous
                            )
                                .stroke(
                                    Color.readingTitle.opacity(isSelected ? 0.48 : 0.20),
                                    lineWidth: SettingsChoiceButtonMetrics.borderWidth
                                )
                        }
                }
                .frame(
                    minWidth: SettingsChoiceButtonMetrics.minimumTouchHeight,
                    minHeight: SettingsChoiceButtonMetrics.minimumTouchHeight
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(SettingsPressButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct SettingsHint: View {
    let text: String

    /// 提示只承担说明作用，不再额外套用图标和圆角底板。
    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Color.readingTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
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
                .padding(.horizontal, 10)
                .frame(minHeight: 30)
                .background {
                    Capsule(style: .continuous)
                        .fill(buttonBackgroundColor)
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(buttonBorderColor, lineWidth: 0.8)
                        }
                }
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
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
    /// 保留即时明暗反馈，不再让设置按钮缩放或播放缓动动画。
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.84 : 1)
    }
}
