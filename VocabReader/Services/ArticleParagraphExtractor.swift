import Foundation

struct ArticleParagraphExtractor {
    func extract(from article: Article) -> [ArticleParagraph] {
        let normalizedContent = article.content.replacingOccurrences(of: "\r\n", with: "\n")
        if article.scene == .dialogue {
            return extractDialogueBlocks(from: normalizedContent)
        }

        let lines = normalizedContent.components(separatedBy: "\n")
        var paragraphs: [ArticleParagraph] = []
        var currentLines: [String] = []

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                appendParagraph(from: currentLines, into: &paragraphs)
                currentLines.removeAll(keepingCapacity: true)
                continue
            }

            currentLines.append(line)
        }

        appendParagraph(from: currentLines, into: &paragraphs)
        return paragraphs
    }

    private func extractDialogueBlocks(from content: String) -> [ArticleParagraph] {
        let lines = content
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var paragraphs: [ArticleParagraph] = []
        var index = 0
        var lineIndex = 0

        while lineIndex < lines.count {
            let nextIndex = min(lineIndex + 2, lines.count)
            let content = lines[lineIndex..<nextIndex].joined(separator: "\n")
            paragraphs.append(ArticleParagraph(index: index, content: content))
            index += 1
            lineIndex = nextIndex
        }

        return paragraphs
    }

    private func appendParagraph(from lines: [String], into paragraphs: inout [ArticleParagraph]) {
        guard !lines.isEmpty else { return }

        let content = lines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        paragraphs.append(ArticleParagraph(index: paragraphs.count, content: content))
    }
}
