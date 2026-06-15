import Foundation

struct ArticleParagraphExtractor {
    /// 根据文章体裁拆分段落，并把文章级词汇命中范围转换成段落内范围。
    func extract(from article: Article) -> [ArticleParagraph] {
        let normalizedContent = article.content.replacingOccurrences(of: "\r\n", with: "\n")
        let normalizedOccurrences = article.content == normalizedContent ? article.vocabularyOccurrences : []
        if article.scene == .dialogue {
            return extractDialogueBlocks(from: normalizedContent, occurrences: normalizedOccurrences)
        }

        let lines = normalizedContent.components(separatedBy: "\n")
        var paragraphs: [ArticleParagraph] = []
        var currentLines: [String] = []
        var currentStartLocation: Int?
        var currentLocation = 0

        for (lineIndex, line) in lines.enumerated() {
            let lineLength = (line as NSString).length
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                appendParagraph(
                    from: currentLines,
                    blockStartLocation: currentStartLocation,
                    occurrences: normalizedOccurrences,
                    into: &paragraphs
                )
                currentLines.removeAll(keepingCapacity: true)
                currentStartLocation = nil
                currentLocation += lineLength + newlineLength(after: lineIndex, totalLineCount: lines.count)
                continue
            }

            if currentLines.isEmpty {
                currentStartLocation = currentLocation
            }
            currentLines.append(line)
            currentLocation += lineLength + newlineLength(after: lineIndex, totalLineCount: lines.count)
        }

        appendParagraph(
            from: currentLines,
            blockStartLocation: currentStartLocation,
            occurrences: normalizedOccurrences,
            into: &paragraphs
        )
        return paragraphs
    }

    /// 对话体裁按两行一组展示，同时保留每一行在原文里的位置用于 range 转换。
    private func extractDialogueBlocks(
        from content: String,
        occurrences: [ArticleVocabularyOccurrence]
    ) -> [ArticleParagraph] {
        let lines = dialogueLines(in: content)

        var paragraphs: [ArticleParagraph] = []
        var index = 0
        var lineIndex = 0

        while lineIndex < lines.count {
            let nextIndex = min(lineIndex + 2, lines.count)
            let groupedLines = Array(lines[lineIndex..<nextIndex])
            let content = groupedLines.map(\.content).joined(separator: "\n")
            let paragraphOccurrences = dialogueOccurrences(
                in: groupedLines,
                occurrences: occurrences
            )
            paragraphs.append(
                ArticleParagraph(
                    index: index,
                    content: content,
                    vocabularyOccurrences: paragraphOccurrences
                )
            )
            index += 1
            lineIndex = nextIndex
        }

        return paragraphs
    }

    /// 把普通段落加入结果，并将落在该段内的文章级命中范围平移成段落级范围。
    private func appendParagraph(
        from lines: [String],
        blockStartLocation: Int?,
        occurrences: [ArticleVocabularyOccurrence],
        into paragraphs: inout [ArticleParagraph]
    ) {
        guard !lines.isEmpty else { return }
        guard let blockStartLocation else { return }

        let rawContent = lines.joined(separator: "\n")
        let content = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        let rawNSString = rawContent as NSString
        let trimmedRangeInBlock = rawNSString.range(of: content)
        let paragraphRange = NSRange(
            location: blockStartLocation + max(trimmedRangeInBlock.location, 0),
            length: (content as NSString).length
        )
        let paragraphOccurrences = shiftedOccurrences(
            occurrences,
            inside: paragraphRange,
            shiftingBy: paragraphRange.location
        )

        paragraphs.append(
            ArticleParagraph(
                index: paragraphs.count,
                content: content,
                vocabularyOccurrences: paragraphOccurrences
            )
        )
    }

    /// 计算当前位置后是否还有换行符，保持 UTF-16 位置和 NSString range 一致。
    private func newlineLength(after lineIndex: Int, totalLineCount: Int) -> Int {
        lineIndex < totalLineCount - 1 ? 1 : 0
    }

    /// 找出段落范围内的命中项，并把 range.location 转成段落内位置。
    private func shiftedOccurrences(
        _ occurrences: [ArticleVocabularyOccurrence],
        inside range: NSRange,
        shiftingBy offset: Int
    ) -> [ArticleVocabularyOccurrence] {
        occurrences.compactMap { occurrence in
            guard contains(occurrence.range, in: range) else { return nil }

            return ArticleVocabularyOccurrence(
                word: occurrence.word,
                surfaceText: occurrence.surfaceText,
                range: NSRange(
                    location: occurrence.range.location - offset,
                    length: occurrence.range.length
                )
            )
        }
    }

    /// 解析对话中的非空行，记录清理空白后的内容和原文 UTF-16 range。
    private func dialogueLines(in content: String) -> [DialogueLine] {
        let lines = content.components(separatedBy: "\n")
        var result: [DialogueLine] = []
        var currentLocation = 0

        for (lineIndex, line) in lines.enumerated() {
            let lineLength = (line as NSString).length
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if !trimmed.isEmpty {
                let trimmedRange = (line as NSString).range(of: trimmed)
                result.append(
                    DialogueLine(
                        content: trimmed,
                        range: NSRange(
                            location: currentLocation + trimmedRange.location,
                            length: (trimmed as NSString).length
                        )
                    )
                )
            }

            currentLocation += lineLength + newlineLength(after: lineIndex, totalLineCount: lines.count)
        }

        return result
    }

    /// 把对话行内命中项转换到两行合并后的段落坐标。
    private func dialogueOccurrences(
        in lines: [DialogueLine],
        occurrences: [ArticleVocabularyOccurrence]
    ) -> [ArticleVocabularyOccurrence] {
        var result: [ArticleVocabularyOccurrence] = []
        var paragraphLocation = 0

        for (lineIndex, line) in lines.enumerated() {
            let shifted = shiftedOccurrences(
                occurrences,
                inside: line.range,
                shiftingBy: line.range.location - paragraphLocation
            )
            result.append(contentsOf: shifted)
            paragraphLocation += (line.content as NSString).length + newlineLength(after: lineIndex, totalLineCount: lines.count)
        }

        return result
    }

    /// 判断一个命中范围是否完整落在段落或对话行范围内。
    private func contains(_ occurrenceRange: NSRange, in containerRange: NSRange) -> Bool {
        occurrenceRange.location >= containerRange.location &&
            occurrenceRange.location + occurrenceRange.length <= containerRange.location + containerRange.length
    }
}

private struct DialogueLine {
    let content: String
    let range: NSRange
}
