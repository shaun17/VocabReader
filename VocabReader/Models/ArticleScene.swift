import Foundation

enum ArticleScene: String, CaseIterable, Identifiable, Codable {
    case dialogue = "对话"
    case science  = "科普"
    case novel    = "小说"

    var id: String { rawValue }

    /// 返回体裁对应的英文描述，供文章生成 Prompt 使用。
    var promptDescription: String {
        switch self {
        case .dialogue: return "a dialogue between two people"
        case .science:  return "a popular science explainer"
        case .novel:    return "a short fictional story"
        }
    }

    /// 返回体裁的格式约束，确保输出结构适合移动端阅读。
    var formatInstructions: String {
        switch self {
        case .dialogue:
            return """
            Use clear dialogue formatting. Every spoken turn must start on a new line with a speaker label, \
            for example "A:" and "B:". Keep most turns to 1-2 sentences. Do not collapse the dialogue into large prose paragraphs.
            """
        case .science:
            return """
            Use short explanatory paragraphs separated by blank lines. \
            Each paragraph should focus on one idea and usually stay within 1-3 sentences.
            """
        case .novel:
            return """
            Use 3-5 short narrative paragraphs separated by blank lines. Each paragraph should usually be 1-3 sentences. \
            Keep the structure easy to scan on a phone screen.
            """
        }
    }

    /// 返回体裁标签图标，供界面展示使用。
    var systemImageName: String {
        switch self {
        case .dialogue:
            return "bubble.left.and.bubble.right"
        case .science:
            return "flask"
        case .novel:
            return "book.closed"
        }
    }
}
