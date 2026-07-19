import Foundation

struct ArticleVocabularyMarkupParseResult {
    let content: String
    let occurrences: [ArticleVocabularyOccurrence]
    let missingWords: [VocabWord]
}

struct ArticleVocabularyMarkupParser {
    private static let markerPattern = #"<vocab\s+id="([^"]+)">([\s\S]*?)</vocab>"#
    private static let strayTagPattern = #"</?\s*vocab\b[^>]*>"#
    private static let malformedOpeningTagPattern = #"<\s*vocab\b(?:\s+id="[^"\s>]*)?"#
    private static let markdownEmphasisPatterns = [
        #"\*\*([\s\S]*?)\*\*"#,
        #"__([\s\S]*?)__"#
    ]

    /// 解析 LLM 生成的内联词汇标记，返回去标签正文、命中范围和缺失目标词。
    func parse(
        content: String,
        targetWords: [VocabWord],
        markerWordByID: [String: VocabWord] = [:]
    ) -> ArticleVocabularyMarkupParseResult {
        var targetWordByID = targetWords.reduce(into: [String: VocabWord]()) { result, word in
            guard result[word.id] == nil else { return }
            result[word.id] = word
        }
        markerWordByID.forEach { markerID, word in
            targetWordByID[markerID] = word
        }
        let normalizedContent = removingMarkdownEmphasis(from: content)
        let nsContent = normalizedContent as NSString
        let fullRange = NSRange(location: 0, length: nsContent.length)
        let regex = try? NSRegularExpression(pattern: Self.markerPattern)
        let matches = regex?.matches(in: normalizedContent, range: fullRange) ?? []

        var cleanContent = ""
        var occurrences: [ArticleVocabularyOccurrence] = []
        var coveredWordIDs = Set<String>()
        var currentLocation = 0

        for match in matches {
            appendUnmarkedText(
                from: nsContent,
                before: match.range,
                currentLocation: &currentLocation,
                cleanContent: &cleanContent
            )

            appendMarkedText(
                from: nsContent,
                match: match,
                targetWordByID: targetWordByID,
                cleanContent: &cleanContent,
                occurrences: &occurrences,
                coveredWordIDs: &coveredWordIDs
            )

            currentLocation = match.range.location + match.range.length
        }

        if currentLocation < nsContent.length {
            cleanContent += sanitizedUnmarkedText(nsContent.substring(from: currentLocation))
        }

        let unmarkedWords = targetWords.filter { !coveredWordIDs.contains($0.id) }
        let fallbackOccurrences = TargetWordMatcher(targetWords: unmarkedWords).occurrences(
            in: cleanContent,
            excluding: occurrences.map(\.range)
        )
        occurrences.append(contentsOf: fallbackOccurrences)

        // LLM 标记是最精确的词组证据；没给标记时，再用本地单词和短语词形匹配兜底，避免整批误判缺失。
        let missingWords = TargetWordMatcher.missingWords(in: cleanContent, targetWords: unmarkedWords)
        return ArticleVocabularyMarkupParseResult(
            content: cleanContent,
            occurrences: occurrences.sorted { $0.range.location < $1.range.location },
            missingWords: missingWords
        )
    }

    /// 清掉模型擅自添加的 Markdown 粗体标记，让正文和词汇 range 从解析开始就使用同一份干净文本。
    private func removingMarkdownEmphasis(from content: String) -> String {
        Self.markdownEmphasisPatterns.reduce(content) { current, pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return current }
            let range = NSRange(location: 0, length: (current as NSString).length)
            return regex.stringByReplacingMatches(in: current, range: range, withTemplate: "$1")
        }
    }

    /// 把标记前的普通正文原样追加到最终正文，保证非词汇文本不丢失。
    private func appendUnmarkedText(
        from nsContent: NSString,
        before markerRange: NSRange,
        currentLocation: inout Int,
        cleanContent: inout String
    ) {
        guard markerRange.location > currentLocation else { return }

        let prefixRange = NSRange(
            location: currentLocation,
            length: markerRange.location - currentLocation
        )
        cleanContent += sanitizedUnmarkedText(nsContent.substring(with: prefixRange))
    }

    /// 把单个词汇标记剥离成正文片段；只有合法目标词 ID 才计入覆盖结果。
    private func appendMarkedText(
        from nsContent: NSString,
        match: NSTextCheckingResult,
        targetWordByID: [String: VocabWord],
        cleanContent: inout String,
        occurrences: inout [ArticleVocabularyOccurrence],
        coveredWordIDs: inout Set<String>
    ) {
        guard match.numberOfRanges >= 3 else { return }

        let id = nsContent.substring(with: match.range(at: 1))
        let surfaceText = nsContent.substring(with: match.range(at: 2))
        let occurrenceRange = NSRange(
            location: (cleanContent as NSString).length,
            length: (surfaceText as NSString).length
        )

        cleanContent += surfaceText

        guard let word = targetWordByID[id], !surfaceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        occurrences.append(
            ArticleVocabularyOccurrence(
                word: word,
                surfaceText: surfaceText,
                range: occurrenceRange
            )
        )
        coveredWordIDs.insert(word.id)
    }

    /// 清理没有成对命中的残留 vocab 标签，避免模型输出半截标签时污染正文。
    private func sanitizedUnmarkedText(_ text: String) -> String {
        let withoutClosedStrayTags = text.replacingOccurrences(
            of: Self.strayTagPattern,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        let withoutMalformedOpeningTags = withoutClosedStrayTags.replacingOccurrences(
            of: Self.malformedOpeningTagPattern,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return withoutMalformedOpeningTags.replacingOccurrences(
            of: #" {2,}"#,
            with: " ",
            options: [.regularExpression]
        )
    }
}
