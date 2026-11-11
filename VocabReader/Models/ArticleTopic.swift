import Foundation

enum ArticleTopic: String, CaseIterable, Identifiable, Codable {
    case general     = "通用"
    case campus      = "校园"
    case workplace   = "职场"
    case travel      = "旅行"
    case food        = "美食"
    case psychology  = "心理"
    case culture     = "文化"
    case environment = "环境"
    case finance     = "财经"
    case sports      = "体育"
    case technology  = "科技"
    case ai          = "AI"
    case medical     = "医疗"
    case customer    = "客户"

    var id: String { rawValue }

    /// 设置页二级列表里的中文说明，帮助用户快速判断主题范围。
    var summary: String {
        switch self {
        case .general:     return "日常生活里常见的话题"
        case .campus:      return "课堂、考试、宿舍和社团"
        case .workplace:   return "会议、汇报、求职和同事相处"
        case .travel:      return "出行规划、交通住宿和异地见闻"
        case .food:        return "下厨、点餐和饮食习惯"
        case .psychology:  return "情绪、习惯、拖延和人际沟通"
        case .culture:     return "历史、艺术、节日和文化差异"
        case .environment: return "天气、自然、环保和城市生活"
        case .finance:     return "预算、储蓄、消费和日常经济"
        case .sports:      return "训练、比赛、健身和观赛"
        case .technology:  return "软件产品、工具和工程协作"
        case .ai:          return "AI 概念、模型使用和工作流"
        case .medical:     return "健康常识和就医沟通"
        case .customer:    return "客户沟通、需求讨论和交付"
        }
    }

    /// 二级列表按分组展示，避免十几个主题平铺成一大片。
    var group: ArticleTopicGroup {
        switch self {
        case .general, .campus, .workplace, .travel, .food, .sports:
            return .daily
        case .psychology, .culture, .environment, .finance:
            return .humanities
        case .technology, .ai, .medical, .customer:
            return .professional
        }
    }

    /// 返回主题对应的英文描述，供文章生成 Prompt 使用。
    var promptDescription: String {
        switch self {
        case .general:
            return "everyday life and broadly applicable topics"
        case .campus:
            return "student life, studying, and school or university experiences"
        case .workplace:
            return "office life, teamwork, careers, and professional growth"
        case .travel:
            return "travel, transportation, and experiences in unfamiliar places"
        case .food:
            return "food, cooking, restaurants, and eating habits"
        case .psychology:
            return "everyday psychology, emotions, habits, and relationships"
        case .culture:
            return "history, art, traditions, and cultural differences"
        case .environment:
            return "nature, climate, sustainability, and city living"
        case .finance:
            return "personal finance, spending, saving, and everyday economics"
        case .sports:
            return "sports, exercise, training, and competition"
        case .technology:
            return "technology concepts, tools, and engineering work"
        case .ai:
            return "artificial intelligence concepts, products, and workflows"
        case .medical:
            return "general medical knowledge and health education"
        case .customer:
            return "customer cases, business collaboration, and workplace communication"
        }
    }

    /// 返回主题内容边界，确保模型围绕指定领域组织内容。
    var topicInstructions: String {
        switch self {
        case .general:
            return "Keep the content grounded in familiar daily situations so the article stays easy to understand."
        case .campus:
            return "Focus on classes, exams, group projects, dorm life, clubs, part-time jobs, or conversations with teachers and classmates."
        case .workplace:
            return "Focus on meetings, deadlines, feedback, job interviews, career choices, or working with colleagues and managers."
        case .travel:
            return "Focus on planning trips, airports and stations, hotels, getting lost, local customs, or unexpected problems on the road."
        case .food:
            return "Focus on cooking at home, ordering and dining out, ingredients, food traditions, or changing eating habits."
        case .psychology:
            return "Focus on relatable everyday psychology such as motivation, stress, procrastination, habits, decision-making, or communication in relationships."
        case .culture:
            return "Focus on museums, historical places, festivals, art, language, or how customs differ between places and generations."
        case .environment:
            return "Focus on weather and seasons, wildlife, recycling, energy use, public transport, or local environmental changes."
        case .finance:
            return "Focus on budgeting, saving, shopping decisions, renting, side income, or how everyday prices and money choices affect people."
        case .sports:
            return "Focus on training, matches, team spirit, injuries and recovery, fitness routines, or being a fan."
        case .technology:
            return "Focus on practical technology scenarios, product usage, software work, or engineering communication."
        case .ai:
            return "Focus on AI concepts, model usage, product workflows, or collaboration around AI systems."
        case .medical:
            return "Focus on general medical education, basic health knowledge, or communication in care settings."
        case .customer:
            return "Focus on customer cases, business meetings, requirement discussions, delivery updates, or account communication."
        }
    }

    /// 标记该主题是否需要启用更强的真实性约束；日常生活类主题只要求合理自洽。
    var requiresStrictFactConstraint: Bool {
        switch self {
        case .general, .campus, .workplace, .travel, .food, .sports:
            return false
        case .psychology, .culture, .environment, .finance, .technology, .ai, .medical, .customer:
            return true
        }
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
        case .psychology:
            baseInstructions += """
             Do not cite specific experiments or researchers unless they are widely known, and do not give clinical diagnoses or therapy advice.
            """
        case .culture:
            baseInstructions += """
             Only mention historical dates, people, and events that are well established; do not invent historical facts.
            """
        case .environment:
            baseInstructions += """
             Avoid made-up climate figures, emission numbers, or policy claims.
            """
        case .finance:
            baseInstructions += """
             Do not give specific investment advice, predict market movements, or invent interest rates, prices, or returns.
            """
        case .general, .campus, .workplace, .travel, .food, .sports:
            break
        }

        return baseInstructions
    }

    /// 返回主题标签图标，供界面展示使用。
    var systemImageName: String {
        switch self {
        case .general:     return "square.grid.2x2"
        case .campus:      return "graduationcap"
        case .workplace:   return "building.2"
        case .travel:      return "airplane"
        case .food:        return "fork.knife"
        case .psychology:  return "brain.head.profile"
        case .culture:     return "building.columns"
        case .environment: return "leaf"
        case .finance:     return "chart.line.uptrend.xyaxis"
        case .sports:      return "figure.run"
        case .technology:  return "desktopcomputer"
        case .ai:          return "cpu"
        case .medical:     return "cross.case"
        case .customer:    return "briefcase"
        }
    }
}

enum ArticleTopicGroup: String, CaseIterable, Identifiable {
    case daily = "生活"
    case humanities = "人文"
    case professional = "专业"

    var id: String { rawValue }

    var topics: [ArticleTopic] {
        ArticleTopic.allCases.filter { $0.group == self }
    }
}
