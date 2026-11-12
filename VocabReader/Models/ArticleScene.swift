import Foundation

enum ArticleScene: String, CaseIterable, Identifiable, Codable {
    case dialogue  = "对话"
    case science   = "科普"
    case novel     = "小说"
    case news      = "新闻"
    case email     = "邮件"
    case essay     = "随笔"
    case opinion   = "评论"
    case interview = "访谈"

    var id: String { rawValue }

    /// 设置页二级列表里的中文说明。
    var summary: String {
        switch self {
        case .dialogue:  return "两人围绕一件事你来我往"
        case .science:   return "把一个问题讲清楚"
        case .novel:     return "一个场景里的小故事"
        case .news:      return "导语、背景和各方反应"
        case .email:     return "有称呼和署名的一封邮件"
        case .essay:     return "第一人称的经历与感悟"
        case .opinion:   return "亮出观点并给出理由"
        case .interview: return "采访者提问，受访者讲述"
        }
    }

    /// 旧版本只有这三种体裁；用于判断哪些体裁是升级后新增的，需要默认开启。
    static let legacyCases: [ArticleScene] = [.dialogue, .science, .novel]

    /// 返回体裁对应的英文描述，供文章生成 Prompt 使用。
    var promptDescription: String {
        switch self {
        case .dialogue:  return "a dialogue between two people"
        case .science:   return "a popular science explainer"
        case .novel:     return "a short fictional story"
        case .news:      return "a short news report"
        case .email:     return "an email from one person to another"
        case .essay:     return "a first-person personal essay"
        case .opinion:   return "an opinion column"
        case .interview: return "an interview transcript"
        }
    }

    /// 对话和访谈逐行带说话人名字，阅读页按两行一组展示。
    var usesSpeakerLines: Bool {
        switch self {
        case .dialogue, .interview: return true
        default: return false
        }
    }

    /// 返回体裁的格式约束；段落或对话轮数随篇幅计划变化，确保输出结构适合移动端阅读。
    /// 分段生成时只有最后一段 `includesEnding`，避免中间段落提前收尾。
    /// `speakers` 只在开篇传入；续写段为 nil，要求沿用前文已经出现的名字。
    func formatInstructions(
        for plan: ArticleLengthPlan,
        includesEnding: Bool = true,
        speakers: SpeakerPair? = nil
    ) -> String {
        let paragraphs = "\(plan.paragraphRange.lowerBound)-\(plan.paragraphRange.upperBound)"
        let turns = "\(plan.dialogueTurnRange.lowerBound)-\(plan.dialogueTurnRange.upperBound)"

        switch self {
        case .dialogue:
            let ending = includesEnding ? " End with a useful outcome or changed understanding." : ""
            return """
            Use clear dialogue formatting. \(speakerLabelInstruction(speakers)) \
            Write about \(turns) turns, and keep most turns to 1-2 sentences. Do not collapse the dialogue into large prose paragraphs. \
            Build the dialogue around one realistic situation with a concrete problem, decision, or mild conflict that readers may meet in daily life, study, work, service, travel, or relationships. \
            Each speaker should have a clear goal, emotion, and response strategy, so the exchange has tension and progression instead of flat turn-taking. \
            Both speakers must actively drive the conversation by asking, challenging, clarifying, proposing, refusing, adjusting, or deciding. \
            Do not make one speaker only ask questions while the other only agrees, explains, or confirms. \
            Keep the conversation on the same topic; do not abruptly switch subjects after a target word appears. \
            Include reusable conversation skills such as politely disagreeing, asking for clarification, showing empathy, negotiating, apologizing, giving feedback, or making a request; show them naturally in the spoken lines, not as explanations. \
            Avoid shallow one-question-one-answer exchanges and generic filler.\(ending)
            """
        case .interview:
            let ending = includesEnding ? " Close with a final question and a reflective answer that sums up the guest's view." : ""
            return """
            Format it as an interview transcript. \(speakerLabelInstruction(speakers, roles: ("interviewer", "guest"))) \
            Write about \(turns) turns. Questions are usually 1 sentence; answers are usually 2-3 sentences. \
            The guest has real experience or expertise related to the topic, and the interviewer follows up on what the guest just said instead of reading a fixed list of questions. \
            Let the guest give concrete examples, admit uncertainty, or push back on an assumption.\(ending)
            """
        case .science:
            return """
            Use \(paragraphs) short explanatory paragraphs separated by blank lines. \
            Each paragraph should focus on one idea and usually be 2-4 sentences. \
            Build a clear explanation arc: introduce one question or problem, develop it step by step, and connect each paragraph back to the same idea.
            """
        case .novel:
            return """
            Use \(paragraphs) short narrative paragraphs separated by blank lines. Each paragraph should usually be 2-4 sentences. \
            Give the characters real first names that fit the setting; vary names across cultures and avoid overused defaults such as Maya, Sarah, Emma, Alex, or John. \
            Stay inside one scene or conflict; each paragraph must move it forward through action, reaction, or consequence.
            """
        case .news:
            return """
            Write in a neutral news style using \(paragraphs) short paragraphs separated by blank lines. \
            Open with a lead paragraph that states what happened, who is involved, and why it matters. \
            Later paragraphs add background, reactions, or quotes from people involved, and what may happen next. \
            Report one local, community, or small-scale event; keep it clearly fictional and do not attribute statements to real public figures or organizations.
            """
        case .email:
            let closing = includesEnding ? " End with a clear next step and a sign-off line with the sender's first name." : ""
            return """
            Format it as one email. Start with a greeting line such as "Hi Daniel," on its own line, then \(paragraphs) short paragraphs separated by blank lines. \
            The sender has one clear purpose: asking, updating, apologizing, declining, thanking, or following up, and the tone fits the relationship between the two people. \
            Use real first names and do not write a subject line.\(closing)
            """
        case .essay:
            return """
            Write in the first person using \(paragraphs) short reflective paragraphs separated by blank lines, each usually 2-4 sentences. \
            Start from one specific moment or small experience, then move toward what the writer noticed, felt, or changed their mind about. \
            Keep it personal and concrete rather than a general lecture.
            """
        case .opinion:
            return """
            Use \(paragraphs) short paragraphs separated by blank lines, each usually 2-4 sentences. \
            State one clear position early, support it with reasons and concrete examples, acknowledge a reasonable counterargument and respond to it. \
            Keep the tone persuasive but fair.
            """
        }
    }

    /// 说话人标签：开篇给出随机名字，续写段要求沿用前文名字；不再使用 A/B 这种占位标签。
    private func speakerLabelInstruction(
        _ speakers: SpeakerPair?,
        roles: (String, String)? = nil
    ) -> String {
        let format = "Every spoken turn must start on a new line with the speaker's first name followed by a colon. Never use placeholder labels such as \"A:\", \"B:\", or \"Speaker 1:\"."
        guard let speakers else {
            return "\(format) Keep exactly the same speaker names used in the previous content."
        }
        let cast: String
        if let roles {
            cast = "The \(roles.0) is \(speakers.first) and the \(roles.1) is \(speakers.second)"
        } else {
            cast = "The two speakers are \(speakers.first) and \(speakers.second)"
        }
        return "\(cast); label their turns exactly as \"\(speakers.first):\" and \"\(speakers.second):\". \(format)"
    }

    /// 返回体裁标签图标，供界面展示使用。
    var systemImageName: String {
        switch self {
        case .dialogue:  return "bubble.left.and.bubble.right"
        case .science:   return "flask"
        case .novel:     return "book.closed"
        case .news:      return "newspaper"
        case .email:     return "envelope"
        case .essay:     return "pencil.line"
        case .opinion:   return "megaphone"
        case .interview: return "mic"
        }
    }
}

/// 对话类体裁的两位说话人；由代码随机抽取，避免模型每次都用同一组名字。
struct SpeakerPair: Equatable {
    let first: String
    let second: String

    static let namePool = [
        "Daniel", "Priya", "Marcus", "Yuki", "Elena", "Omar", "Grace", "Lucas",
        "Hannah", "Mateo", "Chloe", "Ravi", "Nina", "Ethan", "Leila", "Jonas",
        "Sofia", "Kenji", "Amara", "Owen", "Isabel", "Tariq", "Mei", "Samuel",
        "Fatima", "Leo", "Clara", "Andre", "Zoe", "Hiro", "Ana", "Felix"
    ]

    static func random<G: RandomNumberGenerator>(using generator: inout G) -> SpeakerPair {
        let names = namePool.shuffled(using: &generator)
        return SpeakerPair(first: names[0], second: names[1])
    }

    static func random() -> SpeakerPair {
        var generator = SystemRandomNumberGenerator()
        return random(using: &generator)
    }
}
