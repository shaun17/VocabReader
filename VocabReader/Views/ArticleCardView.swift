import SwiftUI

/// 不规则椭圆形，四个角的圆弧半径各不相同，营造轻松手绘感。
private struct BlobShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        // 四个控制点偏移量，让每个角的弧度不同
        let tl: CGFloat = min(w, h) * 0.12  // top-left 较小
        let tr: CGFloat = min(w, h) * 0.18  // top-right 较大
        let br: CGFloat = min(w, h) * 0.10  // bottom-right 较小
        let bl: CGFloat = min(w, h) * 0.16  // bottom-left 较大

        var path = Path()
        // 从顶部中间偏左开始
        path.move(to: CGPoint(x: tl, y: 0))
        // 顶边 — 轻微向上凸起
        path.addQuadCurve(
            to: CGPoint(x: w - tr, y: 0),
            control: CGPoint(x: w * 0.5, y: -h * 0.012)
        )
        // 右上角
        path.addQuadCurve(
            to: CGPoint(x: w, y: tr),
            control: CGPoint(x: w, y: 0)
        )
        // 右边 — 轻微向右凸起
        path.addQuadCurve(
            to: CGPoint(x: w, y: h - br),
            control: CGPoint(x: w + w * 0.008, y: h * 0.5)
        )
        // 右下角
        path.addQuadCurve(
            to: CGPoint(x: w - br, y: h),
            control: CGPoint(x: w, y: h)
        )
        // 底边
        path.addQuadCurve(
            to: CGPoint(x: bl, y: h),
            control: CGPoint(x: w * 0.5, y: h + h * 0.010)
        )
        // 左下角
        path.addQuadCurve(
            to: CGPoint(x: 0, y: h - bl),
            control: CGPoint(x: 0, y: h)
        )
        // 左边
        path.addQuadCurve(
            to: CGPoint(x: 0, y: tl),
            control: CGPoint(x: -w * 0.006, y: h * 0.5)
        )
        // 左上角
        path.addQuadCurve(
            to: CGPoint(x: tl, y: 0),
            control: CGPoint(x: 0, y: 0)
        )
        return path
    }
}

struct ArticleCardView: View {
    let article: Article

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Label(article.scene.rawValue, systemImage: article.scene.systemImageName)
                Label(article.topic.rawValue, systemImage: article.topic.systemImageName)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !article.title.isEmpty {
                Text(article.title)
                    .font(.system(.headline, design: .serif).italic())
                    .foregroundStyle(Color.readingTitle)
            }

            Text(article.content)
                .font(.system(.body, design: .serif))
                .lineLimit(3)
                .foregroundStyle(.primary)

            Text("\(article.targetWords.count) 个词汇")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            BlobShape()
                .fill(Color(red: 0.95, green: 0.93, blue: 0.86))
        }
    }
}
