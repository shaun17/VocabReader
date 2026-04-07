import SwiftUI

struct ArticleReaderView: View {
    let article: Article
    let maiMemo: MaiMemoServiceProtocol

    @State private var selectedWord: VocabWord?

    var body: some View {
        ScrollView {
            articleText
                .padding()
        }
        .navigationTitle(article.scene.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedWord) { word in
            WordDetailSheet(word: word, maiMemo: maiMemo)
                .presentationDetents([.fraction(0.3)])
        }
    }

    @ViewBuilder
    private var articleText: some View {
        Text(buildAttributedString())
            .font(.body)
            .lineSpacing(6)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "word",
                      let spelling = url.host(percentEncoded: false) else { return .discarded }
                selectedWord = article.targetWords.first {
                    $0.spelling.lowercased() == spelling
                }
                return .handled
            })
    }

    private func buildAttributedString() -> AttributedString {
        var result = AttributedString()
        let wordMap = Dictionary(
            uniqueKeysWithValues: article.targetWords.map {
                ($0.spelling.lowercased(), $0)
            }
        )

        // Tokenise by whitespace and newlines, preserve trailing whitespace per token
        let tokens = article.content.components(separatedBy: .whitespacesAndNewlines)
        for (i, token) in tokens.enumerated() {
            let suffix = i < tokens.count - 1 ? " " : ""
            let clean = token.trimmingCharacters(in: .punctuationCharacters).lowercased()

            if let word = wordMap[clean] {
                var span = AttributedString(token + suffix)
                span.foregroundColor = .accentColor
                span.underlineStyle = .single
                span.link = URL(string: "word://\(word.spelling.lowercased())")
                result += span
            } else {
                result += AttributedString(token + suffix)
            }
        }
        return result
    }
}
