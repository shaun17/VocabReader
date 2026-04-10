import SwiftUI

struct ArticleCardView: View {
    let article: Article

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ArticleMetadataChip(
                    title: article.scene.rawValue,
                    systemImage: article.scene.systemImageName
                )
                ArticleMetadataChip(
                    title: article.topic.rawValue,
                    systemImage: article.topic.systemImageName
                )
            }

            Text(article.content)
                .font(.system(.body, design: .serif))
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
}

private struct ArticleMetadataChip: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
    }
}
