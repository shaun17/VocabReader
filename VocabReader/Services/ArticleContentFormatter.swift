import Foundation
import SwiftUI

struct ArticleContentFormatter {
    private let wordPattern = #"[A-Za-z]+(?:['’-][A-Za-z]+)*"#

    func format(article: Article) -> AttributedString {
        format(content: article.content, targetWords: article.targetWords)
    }

    /// 格式化单个段落，只处理正文和单词链接；段落操作按钮由 SwiftUI 原生 Button 承担。
    func formatParagraph(
        content: String,
        targetWords: [VocabWord]
    ) -> AttributedString {
        format(content: content, targetWords: targetWords)
    }

    /// 标记文章里的目标词，供点击查词使用。
    func format(content: String, targetWords: [VocabWord]) -> AttributedString {
        let wordMap = makeWordMap(from: targetWords)

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

    /// 生成大小写不敏感的词表；重复拼写保留第一条，避免详情页格式化时崩溃。
    private func makeWordMap(from targetWords: [VocabWord]) -> [String: VocabWord] {
        targetWords.reduce(into: [:]) { result, word in
            let key = word.spelling.lowercased()
            guard result[key] == nil else { return }
            result[key] = word
        }
    }
}
