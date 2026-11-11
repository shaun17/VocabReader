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

    /// 返回体裁的格式约束；段落或对话轮数随篇幅计划变化，确保输出结构适合移动端阅读。
    /// 分段生成时只有最后一段 `includesEnding`，避免中间段落提前收尾。
    func formatInstructions(for plan: ArticleLengthPlan, includesEnding: Bool = true) -> String {
        switch self {
        case .dialogue:
            let ending = includesEnding ? " End with a useful outcome or changed understanding." : ""
            return """
            Use clear dialogue formatting. Every spoken turn must start on a new line with a speaker label, \
            for example "A:" and "B:". Write about \(plan.dialogueTurnRange.lowerBound)-\(plan.dialogueTurnRange.upperBound) turns, and keep most turns to 1-2 sentences. Do not collapse the dialogue into large prose paragraphs. \
            Build the dialogue around one realistic situation with a concrete problem, decision, or mild conflict that readers may meet in daily life, study, work, service, travel, or relationships. \
            Each speaker should have a clear goal, emotion, and response strategy, so the exchange has tension and progression instead of flat turn-taking. \
            Both speakers must actively drive the conversation by asking, challenging, clarifying, proposing, refusing, adjusting, or deciding. \
            Do not make one speaker only ask questions while the other only agrees, explains, or confirms. \
            Keep the conversation on the same topic; do not abruptly switch subjects after a target word appears. \
            Include reusable conversation skills such as politely disagreeing, asking for clarification, showing empathy, negotiating, apologizing, giving feedback, or making a request; show them naturally in the spoken lines, not as explanations. \
            Avoid shallow one-question-one-answer exchanges and generic filler.\(ending)
            """
        case .science:
            return """
            Use \(plan.paragraphRange.lowerBound)-\(plan.paragraphRange.upperBound) short explanatory paragraphs separated by blank lines. \
            Each paragraph should focus on one idea and usually be 2-4 sentences. \
            Build a clear explanation arc: introduce one question or problem, develop it step by step, and connect each paragraph back to the same idea.
            """
        case .novel:
            return """
            Use \(plan.paragraphRange.lowerBound)-\(plan.paragraphRange.upperBound) short narrative paragraphs separated by blank lines. Each paragraph should usually be 2-4 sentences. \
            Stay inside one scene or conflict; each paragraph must move it forward through action, reaction, or consequence.
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
