import Foundation
import SwiftUI

struct ArticleContentFormatter {
    private let wordPattern = #"[A-Za-z]+(?:['’-][A-Za-z]+)*"#
    private let paragraphActionSeparator = " "

    func format(article: Article) -> AttributedString {
        format(content: article.content, targetWords: article.targetWords)
    }

    func formatParagraph(
        content: String,
        targetWords: [VocabWord],
        paragraphIndex: Int,
        actionTitle: String
    ) -> AttributedString {
        var result = format(content: content, targetWords: targetWords)
        result += AttributedString(paragraphActionSeparator)

        var action = AttributedString(actionTitle)
        action.foregroundColor = .blue
        action.font = .system(size: 11)
        action.link = URL(string: "paragraph://\(paragraphIndex)")
        result += action

        return result
    }

    func format(content: String, targetWords: [VocabWord]) -> AttributedString {
        let wordMap = Dictionary(
            uniqueKeysWithValues: targetWords.map {
                ($0.spelling.lowercased(), $0)
            }
        )

        let nsContent = content as NSString
        let fullRange = NSRange(location: 0, length: nsContent.length)
        let regex = try? NSRegularExpression(pattern: wordPattern)
        let matches = regex?.matches(in: content, range: fullRange) ?? []

        var result = AttributedString()
        var currentLocation = 0

        for match in matches {
            if match.range.location > currentLocation {
                let prefix = nsContent.substring(with: NSRange(location: currentLocation, length: match.range.location - currentLocation))
                result += AttributedString(prefix)
            }

            let token = nsContent.substring(with: match.range)
            if let word = wordMap[token.lowercased()] {
                var span = AttributedString(token)
                span.foregroundColor = .accentColor
                span.underlineStyle = .single
                span.link = URL(string: "word://\(word.spelling.lowercased())")
                result += span
            } else {
                result += AttributedString(token)
            }

            currentLocation = match.range.location + match.range.length
        }

        if currentLocation < nsContent.length {
            let suffix = nsContent.substring(from: currentLocation)
            result += AttributedString(suffix)
        }

        return result
    }
}
