import SwiftUI

struct ArticleCardView: View {
    let article: Article

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(article.scene.rawValue, systemImage: sceneIcon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())

            Text(article.content)
                .font(.body)
                .lineLimit(3)
                .foregroundStyle(.primary)

            Text("\(article.targetWords.count) 个词汇")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }

    private var sceneIcon: String {
        switch article.scene {
        case .news:     return "newspaper"
        case .dialogue: return "bubble.left.and.bubble.right"
        case .story:    return "book"
        case .science:  return "flask"
        }
    }
}
