import SwiftUI

struct ArticleCardView: View {
    let article: Article

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Label(article.scene.rawValue, systemImage: article.scene.systemImageName)
                Label(article.topic.rawValue, systemImage: article.topic.systemImageName)
            }
            .font(.caption)
            .foregroundStyle(Color.readingTextSecondary)

            if !article.title.isEmpty {
                Text(article.title)
                    .font(.system(.headline, design: .serif).italic())
                    .foregroundStyle(Color.readingTitle)
            }

            Text(article.content)
                .font(.system(.body, design: .serif))
                .lineLimit(3)
                .foregroundStyle(Color.readingTextPrimary)

            Text("\(article.targetWords.count) 个词汇")
                .font(.caption)
                .foregroundStyle(Color.readingTextTertiary)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ReadingCardBackground()
        }
    }
}
