import SwiftUI

struct EditableStepper: View {
    let title: String
    let subtitle: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    @State private var text: String
    @FocusState private var isFocused: Bool

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
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.body, design: .serif).weight(.medium))
                    .foregroundStyle(Color.readingTextPrimary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.readingTextSecondary)
            }

            Spacer(minLength: 8)

            HStack(spacing: 2) {
                stepButton(systemImage: "minus", isDisabled: value <= range.lowerBound) {
                    adjustValue(by: -step)
                }

                TextField("", text: $text)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.readingTitle)
                    .frame(width: 46)
                    .focused($isFocused)
                    .onChange(of: isFocused) { _, focused in
                        if !focused { commitText() }
                    }
                    .onSubmit { commitText() }

                stepButton(systemImage: "plus", isDisabled: value >= range.upperBound) {
                    adjustValue(by: step)
                }
            }
            .padding(3)
            .background {
                Capsule(style: .continuous)
                    .fill(Color.readingControlFill)
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(Color.readingRule.opacity(0.95), lineWidth: 0.8)
                    }
            }
        }
        .padding(.vertical, 2)
        .onChange(of: value) { _, newValue in
            if !isFocused { text = String(newValue) }
        }
    }

    /// 生成统一的增减按钮，并保留足够的触控面积和辅助功能标签。
    private func stepButton(
        systemImage: String,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isDisabled ? Color.readingTextSecondary.opacity(0.35) : Color.readingTitle)
                .frame(width: 32, height: 32)
                .contentShape(Circle())
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
