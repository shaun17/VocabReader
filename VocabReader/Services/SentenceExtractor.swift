import Foundation

enum SentenceExtractor {
    static func sentence(containing word: String, in text: String) -> String {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        var match: String?

        nsText.enumerateSubstrings(in: fullRange, options: .bySentences) { substring, _, _, stop in
            guard let substring else { return }
            if substring.localizedCaseInsensitiveContains(word) {
                match = substring.trimmingCharacters(in: .whitespacesAndNewlines)
                stop.pointee = true
            }
        }

        return match ?? text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
