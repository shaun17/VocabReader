import Foundation

enum ArticleTopic: String, CaseIterable, Identifiable, Codable {
    case general = "通用"
    case technology = "科技"
    case medical = "医疗"
    case ai = "AI"
    case customer = "客户"

    var id: String { rawValue }

    /// 返回主题对应的英文描述，供文章生成 Prompt 使用。
    var promptDescription: String {
        switch self {
        case .general:
            return "everyday life and broadly applicable topics"
        case .technology:
            return "technology concepts, tools, and engineering work"
        case .medical:
            return "general medical knowledge and health education"
        case .ai:
            return "artificial intelligence concepts, products, and workflows"
        case .customer:
            return "customer cases, business collaboration, and workplace communication"
        }
    }

    /// 返回主题内容边界，确保模型围绕指定领域组织内容。
    var topicInstructions: String {
        switch self {
        case .general:
            return """
            Keep the content grounded in familiar daily situations so the article stays easy to understand.
            """
        case .technology:
            return """
            Focus on practical technology scenarios, product usage, software work, or engineering communication.
            """
        case .medical:
            return """
            Focus on general medical education, basic health knowledge, or communication in care settings.
            """
        case .ai:
            return """
            Focus on AI concepts, model usage, product workflows, or collaboration around AI systems.
            """
        case .customer:
            return """
            Focus on customer cases, business meetings, requirement discussions, delivery updates, or account communication.
            """
        }
    }

    /// 标记该主题是否需要启用更强的真实性约束。
    var requiresStrictFactConstraint: Bool {
        self != .general
    }

    /// 返回主题对应的真实性约束文案，避免模型编造高风险事实。
    var factConstraintInstructions: String {
        guard requiresStrictFactConstraint else {
            return """
            Keep the details reasonable and internally consistent.
            """
        }

        var baseInstructions = """
        Keep the article factually conservative and realistic. \
        Do not invent precise statistics, study results, clinical evidence, company facts, product releases, customer outcomes, or regulatory claims. \
        If a detail is uncertain, use cautious high-level wording instead of making up specifics.
        """

        switch self {
        case .medical:
            baseInstructions += """
             Provide general educational information only and do not give diagnosis, treatment plans, or urgent medical advice.
            """
        case .technology:
            baseInstructions += """
             Avoid fictional launch dates, benchmark numbers, security claims, or vendor-specific facts unless they are broadly established.
            """
        case .ai:
            baseInstructions += """
             Avoid fictional model capabilities, deployment results, company announcements, or guaranteed automation outcomes.
            """
        case .customer:
            baseInstructions += """
             Avoid fictional customer names, contract details, business metrics, testimonials, or delivery commitments.
            """
        case .general:
            break
        }

        return baseInstructions
    }

    /// 返回主题标签图标，供界面展示使用。
    var systemImageName: String {
        switch self {
        case .general:
            return "square.grid.2x2"
        case .technology:
            return "desktopcomputer"
        case .medical:
            return "cross.case"
        case .ai:
            return "cpu"
        case .customer:
            return "briefcase"
        }
    }
}
