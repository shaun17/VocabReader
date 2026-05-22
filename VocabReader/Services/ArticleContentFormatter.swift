import Foundation
import SwiftUI

struct ArticleContentFormatter {
    /// 格式化整篇文章正文，统一走目标词高亮逻辑。
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
        let matcher = TargetWordMatcher(targetWords: targetWords)

        let nsContent = content as NSString
        let fullRange = NSRange(location: 0, length: nsContent.length)
        let regex = try? NSRegularExpression(pattern: TargetWordMatcher.wordPattern)
        let matches = regex?.matches(in: content, range: fullRange) ?? []

        var result = AttributedString()
        var currentLocation = 0

        for match in matches {
            if match.range.location > currentLocation {
                let prefix = nsContent.substring(with: NSRange(location: currentLocation, length: match.range.location - currentLocation))
                result += AttributedString(prefix)
            }

            let token = nsContent.substring(with: match.range)
            if let word = matcher.word(matching: token) {
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

/// 统一判断目标词和正文 token 是否同源，用于生成后缺词校验和阅读高亮。
struct TargetWordMatcher {
    static let wordPattern = #"[A-Za-z]+(?:['’-][A-Za-z]+)*"#

    private let wordByForm: [String: VocabWord]
    private let canonicalKeyByForm: [String: String]

    /// 建立“可接受词形 -> 目标词”的索引，重复词形保留第一条目标词。
    init(targetWords: [VocabWord]) {
        var wordByForm: [String: VocabWord] = [:]
        var canonicalKeyByForm: [String: String] = [:]

        for word in targetWords {
            let canonicalKey = Self.normalizedToken(word.spelling)
            guard !canonicalKey.isEmpty else { continue }

            for form in Self.acceptedForms(for: canonicalKey) {
                guard wordByForm[form] == nil else { continue }
                wordByForm[form] = word
                canonicalKeyByForm[form] = canonicalKey
            }
        }

        self.wordByForm = wordByForm
        self.canonicalKeyByForm = canonicalKeyByForm
    }

    /// 返回正文 token 对应的目标词；支持原词和常见屈折变化。
    func word(matching token: String) -> VocabWord? {
        wordByForm[Self.normalizedToken(token)]
    }

    /// 找出正文里完全没有出现过的目标词，屈折变化也算作已覆盖。
    static func missingWords(in content: String, targetWords: [VocabWord]) -> [VocabWord] {
        let matcher = TargetWordMatcher(targetWords: targetWords)
        let coveredKeys = Set(tokens(in: content).compactMap { matcher.canonicalKey(matching: $0) })

        return targetWords.filter { word in
            let key = normalizedToken(word.spelling)
            return !key.isEmpty && !coveredKeys.contains(key)
        }
    }

    /// 返回正文 token 命中的目标词规范 key，用于生成后缺词校验。
    private func canonicalKey(matching token: String) -> String? {
        canonicalKeyByForm[Self.normalizedToken(token)]
    }

    /// 从正文中提取英文 token，保持和高亮器相同的分词边界。
    private static func tokens(in content: String) -> [String] {
        let nsContent = content as NSString
        let fullRange = NSRange(location: 0, length: nsContent.length)
        let regex = try? NSRegularExpression(pattern: wordPattern)
        let matches = regex?.matches(in: content, range: fullRange) ?? []

        return matches.map { nsContent.substring(with: $0.range) }
    }

    /// 统一大小写和弯引号，避免同一英文词因为展示字符差异漏匹配。
    private static func normalizedToken(_ token: String) -> String {
        token
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 为目标词生成常见英语屈折形式，覆盖原形到变形、变形回原形两个方向。
    private static func acceptedForms(for base: String) -> Set<String> {
        guard base.range(of: #"^[a-z]+$"#, options: .regularExpression) != nil else {
            return [base]
        }

        return candidateBases(for: base).reduce(into: Set<String>()) { forms, candidate in
            forms.insert(candidate)
            guard candidate.count >= 3 else { return }

            forms.insert(thirdPersonOrPluralForm(of: candidate))
            forms.formUnion(pastTenseForms(of: candidate))
            forms.formUnion(presentParticipleForms(of: candidate))
        }
    }

    /// 从目标词推导可能原形，让 concerns -> concern、managed -> manage 也能同源匹配。
    private static func candidateBases(for word: String) -> Set<String> {
        var candidates: Set<String> = [word]

        if word.hasSuffix("ies"), word.count > 3 {
            candidates.insert("\(word.dropLast(3))y")
        }

        if word.hasSuffix("es"), word.count > 2 {
            candidates.insert(String(word.dropLast(2)))
            candidates.insert(String(word.dropLast()))
        } else if word.hasSuffix("s"), word.count > 1, canDropSinglePluralS(word) {
            candidates.insert(String(word.dropLast()))
        }

        if word.hasSuffix("ied"), word.count > 3 {
            candidates.insert("\(word.dropLast(3))y")
        }

        if word.hasSuffix("ed"), word.count > 2 {
            let stem = String(word.dropLast(2))
            candidates.insert(stem)
            candidates.insert("\(stem)e")
            if let last = stem.last, stem.dropLast().last == last {
                candidates.insert(String(stem.dropLast()))
            }
        }

        if word.hasSuffix("ing"), word.count > 3 {
            let stem = String(word.dropLast(3))
            candidates.insert(stem)
            candidates.insert("\(stem)e")
            if let last = stem.last, stem.dropLast().last == last {
                candidates.insert(String(stem.dropLast()))
            }
        }

        return candidates.filter { $0 == word || $0.count >= 3 }
    }

    /// 生成复数或第三人称单数形式，例如 policy -> policies、watch -> watches。
    private static func thirdPersonOrPluralForm(of base: String) -> String {
        if base.hasSuffix("y"), let previous = base.dropLast().last, isConsonant(previous) {
            return "\(base.dropLast())ies"
        }

        if base.hasSuffix("s") || base.hasSuffix("x") || base.hasSuffix("z") ||
            base.hasSuffix("ch") || base.hasSuffix("sh") || base.hasSuffix("o") {
            return "\(base)es"
        }

        return "\(base)s"
    }

    /// 生成过去式形式；无法判断重音时同时保留普通拼写和双写拼写，避免 open/opened 漏匹配。
    private static func pastTenseForms(of base: String) -> Set<String> {
        if base.hasSuffix("y"), let previous = base.dropLast().last, isConsonant(previous) {
            return ["\(base.dropLast())ied"]
        }

        if base.hasSuffix("e") {
            return ["\(base)d"]
        }

        var forms: Set<String> = ["\(base)ed"]
        if shouldDoubleFinalConsonant(base) {
            forms.insert("\(base)\(base.last!)ed")
        }

        return forms
    }

    /// 生成现在分词形式；无法判断重音时同时保留普通拼写和双写拼写，避免 open/opening 漏匹配。
    private static func presentParticipleForms(of base: String) -> Set<String> {
        if base.hasSuffix("ie") {
            return ["\(base.dropLast(2))ying"]
        }

        if base.hasSuffix("e"), !base.hasSuffix("ee"), !base.hasSuffix("ye"), !base.hasSuffix("oe") {
            return ["\(base.dropLast())ing"]
        }

        var forms: Set<String> = ["\(base)ing"]
        if shouldDoubleFinalConsonant(base) {
            forms.insert("\(base)\(base.last!)ing")
        }

        return forms
    }

    /// 排除 news、analysis 这类词尾 s 本身属于词根的情况，避免误判为复数。
    private static func canDropSinglePluralS(_ word: String) -> Bool {
        let lexicalSEndingWords: Set<String> = ["news", "series", "species"]
        guard !lexicalSEndingWords.contains(word) else { return false }

        return !word.hasSuffix("ss") &&
            !word.hasSuffix("is") &&
            !word.hasSuffix("us") &&
            !word.hasSuffix("ous") &&
            !word.hasSuffix("ness")
    }

    /// 判断是否使用常见的 CVC 双写规则，覆盖 stop/stopped、recur/recurring 这类形式。
    private static func shouldDoubleFinalConsonant(_ base: String) -> Bool {
        let characters = Array(base)
        guard characters.count >= 3 else { return false }

        let last = characters[characters.count - 1]
        let middle = characters[characters.count - 2]
        let first = characters[characters.count - 3]

        guard isConsonant(first), isVowel(middle), isConsonant(last) else { return false }
        return last != "w" && last != "x" && last != "y"
    }

    /// 判断英文元音，用于常见屈折规则。
    private static func isVowel(_ character: Character) -> Bool {
        ["a", "e", "i", "o", "u"].contains(character)
    }

    /// 判断英文辅音，用于常见屈折规则。
    private static func isConsonant(_ character: Character) -> Bool {
        character >= "a" && character <= "z" && !isVowel(character)
    }
}
