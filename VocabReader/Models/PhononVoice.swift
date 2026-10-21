import Foundation

enum PhononAccent: String, CaseIterable, Identifiable {
    case american
    case british

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .american:
            return "美式口音"
        case .british:
            return "英式口音"
        }
    }

    var shortTitle: String {
        switch self {
        case .american:
            return "美式"
        case .british:
            return "英式"
        }
    }
}

/// Phonon 模型自带的常规朗读音色。名称必须与模型包 voices/ 下的文件名一致；
/// 角色音（怪物、巫师等夸张演绎）不适合学习场景，不在此列。
struct PhononVoice: Identifiable, Equatable {
    enum Gender {
        case female
        case male

        var title: String {
            self == .female ? "女" : "男"
        }
    }

    let name: String
    let accent: PhononAccent
    let gender: Gender
    /// 年龄段与音色特点，依据官方 voices.jsonl 的描述整理。
    let summary: String

    var id: String {
        name
    }

    /// 设置页音色行的说明，例如“英式男声 · 中年 · 轻盈，语速舒缓”。
    var detail: String {
        "\(accent.shortTitle)\(gender.title)声 · \(summary)"
    }

    static let defaultName = "Zoey"

    static let catalog: [PhononVoice] = [
        PhononVoice(name: "Zoey", accent: .american, gender: .female, summary: "成年 · 活泼轻快"),
        PhononVoice(name: "Juniper", accent: .american, gender: .female, summary: "青年 · 明朗亲切"),
        PhononVoice(name: "Harper", accent: .american, gender: .female, summary: "成年 · 自信友好"),
        PhononVoice(name: "Everly", accent: .american, gender: .female, summary: "中年 · 柔和放松"),
        PhononVoice(name: "Hadley", accent: .american, gender: .female, summary: "中年 · 平稳温和，吐字清晰"),
        PhononVoice(name: "Delia", accent: .american, gender: .female, summary: "中年 · 低沉干脆"),
        PhononVoice(name: "Easton", accent: .american, gender: .male, summary: "青年 · 有力清脆"),
        PhononVoice(name: "Micah", accent: .american, gender: .male, summary: "青年 · 活力充沛"),
        PhononVoice(name: "Miles", accent: .american, gender: .male, summary: "青年 · 浑厚，起伏明显"),
        PhononVoice(name: "Trevor", accent: .american, gender: .male, summary: "中年 · 中低音，饱满有活力"),
        PhononVoice(name: "Russell", accent: .american, gender: .male, summary: "成年"),
        PhononVoice(name: "Preston", accent: .american, gender: .male, summary: "中年"),
        PhononVoice(name: "Maeve", accent: .british, gender: .female, summary: "成年"),
        PhononVoice(name: "Freya", accent: .british, gender: .female, summary: "少年"),
        PhononVoice(name: "Pippa", accent: .british, gender: .female, summary: "成年"),
        PhononVoice(name: "Elodie-Rose", accent: .british, gender: .female, summary: "少年"),
        PhononVoice(name: "Imogen", accent: .british, gender: .female, summary: "成年"),
        PhononVoice(name: "Lottie", accent: .british, gender: .female, summary: "青年"),
        PhononVoice(name: "Bryony", accent: .british, gender: .female, summary: "中年 · 饱满柔和，语速轻快"),
        PhononVoice(name: "Alfie", accent: .british, gender: .male, summary: "青年 · 有力清脆"),
        PhononVoice(name: "Hugh", accent: .british, gender: .male, summary: "中年 · 轻柔真诚"),
        PhononVoice(name: "Edwin", accent: .british, gender: .male, summary: "中年 · 干练，吐字清晰"),
        PhononVoice(name: "Spencer", accent: .british, gender: .male, summary: "中年 · 轻盈，语速舒缓"),
        PhononVoice(name: "Toby", accent: .british, gender: .male, summary: "成年"),
        PhononVoice(name: "Teddy", accent: .british, gender: .male, summary: "青年"),
    ]

    static func named(_ name: String) -> PhononVoice? {
        catalog.first { $0.name == name }
    }

    static func voices(for accent: PhononAccent) -> [PhononVoice] {
        catalog.filter { $0.accent == accent }
    }

    /// 历史值或未知名称回退到默认音色。
    static func normalizedName(_ name: String?) -> String {
        name.flatMap(named)?.name ?? defaultName
    }
}
