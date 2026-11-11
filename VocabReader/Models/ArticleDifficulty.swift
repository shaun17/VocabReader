import Foundation

/// 文章阅读难度，按 CEFR 等级约束目标词以外的句式和用词。
enum ArticleDifficulty: String, CaseIterable, Identifiable, Codable {
    case elementary = "入门"
    case intermediate = "中级"
    case upperIntermediate = "中高级"
    case advanced = "高级"

    static let `default` = ArticleDifficulty.intermediate

    var id: String { rawValue }

    var cefrLevel: String {
        switch self {
        case .elementary: return "A2"
        case .intermediate: return "B1"
        case .upperIntermediate: return "B2"
        case .advanced: return "C1"
        }
    }

    /// 设置页说明，用国内常见考试水平帮助用户选择。
    var hint: String {
        switch self {
        case .elementary: return "\(cefrLevel) · 短句和高频词，适合初高中水平"
        case .intermediate: return "\(cefrLevel) · 日常常用表达，适合四级左右"
        case .upperIntermediate: return "\(cefrLevel) · 句式更丰富，适合六级、考研水平"
        case .advanced: return "\(cefrLevel) · 接近母语读物，适合雅思 7 分以上"
        }
    }

    /// 目标词本身可能超出该等级，所以只约束周围文字，并要求语境能帮读者理解目标词。
    var promptInstructions: String {
        let style: String
        switch self {
        case .elementary:
            style = "Use mostly high-frequency everyday words, short sentences of about 8-12 words, simple tenses, and few subordinate clauses."
        case .intermediate:
            style = "Use common everyday words and phrasal verbs, sentences of about 10-16 words, and simple compound or complex sentences."
        case .upperIntermediate:
            style = "Use a wider range of vocabulary and sentence structures, such as relative clauses, conditionals, and natural idioms in moderation."
        case .advanced:
            style = "Write like well-edited prose for fluent adult readers, with varied sentence structures and precise, idiomatic word choice, while staying clear."
        }
        return """
        Write for a CEFR \(cefrLevel) English learner. \(style) \
        The target vocabulary items may be above this level; keep the surrounding language at this level so the context makes each target item understandable.
        """
    }
}
