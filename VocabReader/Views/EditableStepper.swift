import SwiftUI

/// 词量输入控件的统一尺寸，视觉外壳紧凑但所有可交互区域不少于 44pt。
enum SettingsStepperMetrics {
    static let rowVerticalPadding: CGFloat = 8
    static let titleSpacing: CGFloat = 3
    static let minimumTouchSize: CGFloat = 44
    static let controlVisualHeight: CGFloat = 36
    static let controlCornerRadius: CGFloat = 10
    static let separatorHeight: CGFloat = 18
    static let maximumValueWidth: CGFloat = 88
}

struct EditableStepper: View {
    let title: String
    let subtitle: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    @State private var text: String
    @FocusState private var isFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var scaledValueFieldWidth: CGFloat = 44

    /// 保存输入框文本副本，使键盘编辑结束前不会反复触发数值规范化。
    init(
        title: String,
        subtitle: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int
    ) {
        self.title = title
        self.subtitle = subtitle
        _value = value
        self.range = range
        self.step = step
        _text = State(initialValue: String(value.wrappedValue))
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    titleContent
                    valueControl
                }
            } else {
                HStack(spacing: 12) {
                    titleContent
                    Spacer(minLength: 12)
                    valueControl
                }
            }
        }
        .padding(.vertical, SettingsStepperMetrics.rowVerticalPadding)
        .onChange(of: value) { _, newValue in
            if !isFocused { text = String(newValue) }
        }
    }

    /// 标题区保持自身优先级，避免右侧数值控件把说明文字挤成窄列。
    private var titleContent: some View {
        VStack(alignment: .leading, spacing: SettingsStepperMetrics.titleSpacing) {
            Text(title)
                .font(.system(.body, design: .serif).weight(.medium))
                .foregroundStyle(Color.readingTextPrimary)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(Color.readingTextSecondary)
        }
        .layoutPriority(1)
    }

    /// 数值、减少和增加共享一个紧凑外壳，内部触控区仍各自保持 44pt。
    private var valueControl: some View {
        HStack(spacing: 0) {
            stepButton(systemImage: "minus", isDisabled: value <= range.lowerBound) {
                adjustValue(by: -step)
            }

            TextField("", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.readingTitle)
                .frame(
                    width: valueFieldWidth,
                    height: SettingsStepperMetrics.minimumTouchSize
                )
                .overlay(alignment: .leading) { controlSeparator }
                .overlay(alignment: .trailing) { controlSeparator }
                .focused($isFocused)
                .onChange(of: isFocused) { _, focused in
                    if !focused { commitText() }
                }
                .onSubmit { commitText() }
                .accessibilityLabel(title)

            stepButton(systemImage: "plus", isDisabled: value >= range.upperBound) {
                adjustValue(by: step)
            }
        }
        .background {
            RoundedRectangle(
                cornerRadius: SettingsStepperMetrics.controlCornerRadius,
                style: .continuous
            )
                .fill(Color.readingControlFill)
                .frame(height: SettingsStepperMetrics.controlVisualHeight)
                .overlay {
                    RoundedRectangle(
                        cornerRadius: SettingsStepperMetrics.controlCornerRadius,
                        style: .continuous
                    )
                        .stroke(Color.readingRule.opacity(0.95), lineWidth: 0.8)
                }
        }
    }

    /// 普通字号保持紧凑，辅助字号按比例扩大数值区，并限制上限以免控件撑满整行。
    private var valueFieldWidth: CGFloat {
        min(
            max(scaledValueFieldWidth, SettingsStepperMetrics.minimumTouchSize),
            SettingsStepperMetrics.maximumValueWidth
        )
    }

    /// 中性细线只划分三个功能区，不额外增加控件宽度。
    private var controlSeparator: some View {
        Rectangle()
            .fill(Color.readingSeparator.opacity(0.72))
            .frame(width: 0.5, height: SettingsStepperMetrics.separatorHeight)
            .allowsHitTesting(false)
    }

    /// 生成统一的增减按钮，并保留足够的触控面积和辅助功能标签。
    private func stepButton(
        systemImage: String,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(isDisabled ? Color.readingTextSecondary.opacity(0.35) : Color.readingTitle)
                .frame(
                    width: SettingsStepperMetrics.minimumTouchSize,
                    height: SettingsStepperMetrics.minimumTouchSize
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(systemImage == "minus" ? "减少\(title)" : "增加\(title)")
    }

    /// 使用步长更新绑定值，并同步键盘文本。
    private func adjustValue(by delta: Int) {
        let newValue = min(max(value + delta, range.lowerBound), range.upperBound)
        value = newValue
        text = String(newValue)
    }

    /// 手动输入同样执行范围限制和步长吸附，避免非法值写入设置草稿。
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
