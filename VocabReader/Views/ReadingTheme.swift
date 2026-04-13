import SwiftUI

extension Color {
    /// 偏暖黄色的阅读背景色，减轻蓝光刺激，适合长时间阅读。
    static let readingBackground = Color(red: 0.98, green: 0.96, blue: 0.90)

    /// 文章标题使用的暖橙色，参考经典书籍排版。
    static let readingTitle = Color(red: 0.80, green: 0.33, blue: 0.12)

    /// 收藏卡片和文章卡片统一使用的暖纸片底色。
    static let readingCardFill = Color(red: 0.95, green: 0.93, blue: 0.86)

    /// 横线颜色，模拟草稿纸/作业本条纹。
    static let readingRule = Color(red: 0.85, green: 0.82, blue: 0.74).opacity(0.5)
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
                    .stroke(Color.readingRule.opacity(0.55), lineWidth: 0.8)
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
