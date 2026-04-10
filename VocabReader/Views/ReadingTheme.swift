import SwiftUI

extension Color {
    /// 偏暖黄色的阅读背景色，减轻蓝光刺激，适合长时间阅读。
    static let readingBackground = Color(red: 0.98, green: 0.96, blue: 0.90)

    /// 文章标题使用的暖橙色，参考经典书籍排版。
    static let readingTitle = Color(red: 0.80, green: 0.33, blue: 0.12)

    /// 横线颜色，模拟草稿纸/作业本条纹。
    static let readingRule = Color(red: 0.85, green: 0.82, blue: 0.74).opacity(0.5)
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
