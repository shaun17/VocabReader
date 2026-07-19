import SwiftUI
import UIKit

/// 阅读界面统一使用的动态色板，同时供 SwiftUI 和 UIKit 控件消费。
enum ReadingPalette {
    static let background = adaptiveColor(
        light: color(250, 245, 230),
        dark: color(33, 30, 26)
    )
    static let cardFill = adaptiveColor(
        light: color(242, 237, 219),
        dark: color(44, 40, 34)
    )
    static let controlFill = adaptiveColor(
        light: color(255, 249, 237),
        dark: color(55, 49, 41)
    )
    static let primaryText = adaptiveColor(
        light: color(44, 41, 37),
        dark: color(222, 214, 201)
    )
    static let secondaryText = adaptiveColor(
        light: color(101, 95, 87),
        dark: color(180, 171, 158)
    )
    static let tertiaryText = adaptiveColor(
        light: color(114, 106, 96),
        dark: color(148, 139, 127)
    )
    static let separator = adaptiveColor(
        light: color(201, 190, 169),
        dark: color(80, 72, 63)
    )
    static let rule = adaptiveColor(
        light: color(222, 213, 194),
        dark: color(59, 54, 47)
    )
    static let accent = adaptiveColor(
        light: color(185, 71, 24),
        dark: color(226, 138, 90)
    )
    static let accentForeground = adaptiveColor(
        light: color(255, 249, 240),
        dark: color(36, 23, 17)
    )
    static let navigationBackground = adaptiveColor(
        light: color(250, 245, 230),
        dark: color(38, 34, 30)
    )
    static let success = adaptiveColor(
        light: color(47, 107, 63),
        dark: color(130, 201, 143)
    )
    static let error = adaptiveColor(
        light: color(179, 38, 30),
        dark: color(255, 138, 128)
    )

    /// 根据当前界面明暗模式返回对应颜色，确保 SwiftUI 与 UIKit 同步切换。
    private static func adaptiveColor(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        }
    }

    /// 使用 0 到 255 的设计值构造颜色，便于直接核对色板规格。
    private static func color(_ red: Int, _ green: Int, _ blue: Int) -> UIColor {
        UIColor(
            red: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: 1
        )
    }
}

extension Color {
    /// 浅色为暖纸张，深色为暖炭黑，避免长时间阅读时受到纯黑背景刺激。
    static let readingBackground = Color(uiColor: ReadingPalette.background)

    /// 文章标题和交互控件使用的动态暖橙强调色。
    static let readingTitle = Color(uiColor: ReadingPalette.accent)

    /// 收藏卡片和文章卡片统一使用的动态纸片底色。
    static let readingCardFill = Color(uiColor: ReadingPalette.cardFill)

    /// 输入框、未选按钮和补充内容使用的内嵌控件底色。
    static let readingControlFill = Color(uiColor: ReadingPalette.controlFill)

    /// 横线颜色，模拟草稿纸/作业本条纹。
    static let readingRule = Color(uiColor: ReadingPalette.rule)

    /// 正文主文字使用低眩光深棕或柔和米白，避免纯黑与纯白的强烈反差。
    static let readingTextPrimary = Color(uiColor: ReadingPalette.primaryText)

    /// 元数据、说明和辅助内容使用的次级文字色。
    static let readingTextSecondary = Color(uiColor: ReadingPalette.secondaryText)

    /// 非关键提示和计数使用的第三级文字色。
    static let readingTextTertiary = Color(uiColor: ReadingPalette.tertiaryText)

    /// 卡片边框和设置分隔线使用的结构色。
    static let readingSeparator = Color(uiColor: ReadingPalette.separator)

    /// 强调色底板上的文字色，分别保证浅色和深色模式的对比度。
    static let readingAccentForeground = Color(uiColor: ReadingPalette.accentForeground)

    /// 导航栏使用比正文背景略有层次的动态底色。
    static let readingNavigationBackground = Color(uiColor: ReadingPalette.navigationBackground)

    /// 成功反馈使用的动态绿色。
    static let readingSuccess = Color(uiColor: ReadingPalette.success)

    /// 错误反馈使用的动态红色。
    static let readingError = Color(uiColor: ReadingPalette.error)
}

/// 阅读页与收藏页共用的辅助动作语义，统一可见文案和图标。
enum ReadingSupplementAction: Equatable {
    case translation
    case analysis

    var title: String {
        switch self {
        case .translation:
            return "翻译"
        case .analysis:
            return "解析"
        }
    }

    var systemImage: String {
        switch self {
        case .translation:
            return "character.book.closed"
        case .analysis:
            return "text.magnifyingglass"
        }
    }
}

/// 把按钮状态收口成跨 SwiftUI/UIKit 共用的展示模型，避免两处文案和状态表达再次漂移。
struct ReadingSupplementActionPresentation: Equatable {
    let action: ReadingSupplementAction
    let isActive: Bool
    let isLoading: Bool
    let isDisabled: Bool

    var title: String {
        action.title
    }

    var systemImage: String {
        action.systemImage
    }

    var accessibilityLabel: String {
        isActive ? "收起\(title)" : title
    }
}

/// “页边批注工具”的统一尺寸令牌，供 SwiftUI 收藏按钮和 UIKit 行尾按钮共同消费。
enum ReadingSupplementActionMetrics {
    /// 同时作为视觉最小高度与触控最小高度，满足移动端 44pt 可点击区域要求。
    static let minimumHeight: CGFloat = 44
    static let horizontalPadding: CGFloat = 10
    static let verticalPadding: CGFloat = 3
    static let contentSpacing: CGFloat = 5
    static let groupSpacing: CGFloat = 8
    static let borderWidth: CGFloat = 0.8
    static let fontPointSize: CGFloat = 12
    static let iconPointSize: CGFloat = 11
}

/// 收藏页使用的阅读辅助按钮；文章页的 UIKit 实现复用同一展示模型和视觉令牌。
struct ReadingSupplementActionButton: View {
    let presentation: ReadingSupplementActionPresentation
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: ReadingSupplementActionMetrics.contentSpacing) {
                actionIcon

                Text(presentation.title)
            }
            .font(.system(size: ReadingSupplementActionMetrics.fontPointSize, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, ReadingSupplementActionMetrics.horizontalPadding)
            .padding(.vertical, ReadingSupplementActionMetrics.verticalPadding)
            .frame(minHeight: ReadingSupplementActionMetrics.minimumHeight)
            .background {
                Capsule(style: .continuous)
                    .fill(backgroundColor)
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(borderColor, lineWidth: ReadingSupplementActionMetrics.borderWidth)
                    }
            }
        }
        .buttonStyle(ReadingSupplementActionButtonStyle())
        .disabled(presentation.isDisabled)
        .opacity(disabledOpacity)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    @ViewBuilder
    private var actionIcon: some View {
        if presentation.isLoading {
            ProgressView()
                .controlSize(.mini)
                .tint(foregroundColor)
        } else {
            Image(systemName: presentation.systemImage)
                .font(.system(size: ReadingSupplementActionMetrics.iconPointSize, weight: .semibold))
        }
    }

    private var foregroundColor: Color {
        presentation.isActive ? .readingAccentForeground : .readingTitle
    }

    private var backgroundColor: Color {
        presentation.isActive ? .readingTitle : .readingControlFill
    }

    private var borderColor: Color {
        Color.readingTitle.opacity(presentation.isActive ? 0.72 : 0.26)
    }

    private var disabledOpacity: Double {
        presentation.isDisabled && !presentation.isLoading ? 0.45 : 1
    }
}

private struct ReadingSupplementActionButtonStyle: ButtonStyle {
    /// 轻微缩放模拟纸面工具被按下的触感，不引入抢眼动画。
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 不规则椭圆形卡片，和首页文章卡片保持同一套手绘纸片视觉。
struct ReadingCardShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let tl: CGFloat = min(w, h) * 0.12
        let tr: CGFloat = min(w, h) * 0.18
        let br: CGFloat = min(w, h) * 0.10
        let bl: CGFloat = min(w, h) * 0.16

        var path = Path()
        path.move(to: CGPoint(x: tl, y: 0))
        path.addQuadCurve(
            to: CGPoint(x: w - tr, y: 0),
            control: CGPoint(x: w * 0.5, y: -h * 0.012)
        )
        path.addQuadCurve(
            to: CGPoint(x: w, y: tr),
            control: CGPoint(x: w, y: 0)
        )
        path.addQuadCurve(
            to: CGPoint(x: w, y: h - br),
            control: CGPoint(x: w + w * 0.008, y: h * 0.5)
        )
        path.addQuadCurve(
            to: CGPoint(x: w - br, y: h),
            control: CGPoint(x: w, y: h)
        )
        path.addQuadCurve(
            to: CGPoint(x: bl, y: h),
            control: CGPoint(x: w * 0.5, y: h + h * 0.010)
        )
        path.addQuadCurve(
            to: CGPoint(x: 0, y: h - bl),
            control: CGPoint(x: 0, y: h)
        )
        path.addQuadCurve(
            to: CGPoint(x: 0, y: tl),
            control: CGPoint(x: -w * 0.006, y: h * 0.5)
        )
        path.addQuadCurve(
            to: CGPoint(x: tl, y: 0),
            control: CGPoint(x: 0, y: 0)
        )
        return path
    }
}

/// 统一的阅读卡片底板，给首页文章卡片和收藏卡片复用。
struct ReadingCardBackground: View {
    var body: some View {
        ReadingCardShape()
            .fill(Color.readingCardFill)
            .overlay {
                ReadingCardShape()
                    .stroke(Color.readingSeparator.opacity(0.72), lineWidth: 0.8)
            }
    }
}

/// 模拟作业本/草稿纸的条纹背景。暖黄底色上绘制等距水平线。
struct LinedPaperBackground: View {
    var lineSpacing: CGFloat = 32

    var body: some View {
        Color.readingBackground
            .overlay {
                GeometryReader { geo in
                    Canvas { context, size in
                        let count = Int(size.height / lineSpacing)
                        for i in 1...max(count, 1) {
                            let y = CGFloat(i) * lineSpacing
                            var path = Path()
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: size.width, y: y))
                            context.stroke(path, with: .color(Color.readingRule), lineWidth: 0.5)
                        }
                    }
                }
            }
            .ignoresSafeArea()
    }
}
