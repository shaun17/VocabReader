import Foundation

enum ArticleScene: String, CaseIterable, Identifiable {
    case dialogue = "对话"
    case story    = "故事"
    case science  = "科普"

    var id: String { rawValue }

    var promptDescription: String {
        switch self {
        case .dialogue: return "a dialogue between two people"
        case .story:    return "a short story"
        case .science:  return "a popular science explainer"
        }
    }

    var formatInstructions: String {
        switch self {
        case .dialogue:
            return """
            Use clear dialogue formatting. Every spoken turn must start on a new line with a speaker label, \
            for example "A:" and "B:". Keep most turns to 1-2 sentences. Do not collapse the dialogue into large prose paragraphs.
            """
        case .story:
            return """
            Use 3-5 short paragraphs separated by blank lines. Each paragraph should usually be 1-3 sentences. \
            Keep the structure easy to scan on a phone screen.
            """
        case .science:
            return """
            Use short explanatory paragraphs separated by blank lines. \
            Each paragraph should focus on one idea and usually stay within 1-3 sentences.
            """
        }
    }
}
