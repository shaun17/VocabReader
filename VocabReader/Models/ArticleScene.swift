import Foundation

enum ArticleScene: String, CaseIterable, Identifiable {
    case news     = "新闻"
    case dialogue = "对话"
    case story    = "故事"
    case science  = "科普"

    var id: String { rawValue }

    var promptDescription: String {
        switch self {
        case .news:     return "a news article"
        case .dialogue: return "a dialogue between two people"
        case .story:    return "a short story"
        case .science:  return "a science essay"
        }
    }
}
