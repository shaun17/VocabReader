import Foundation

/// 文章朗读使用的语音引擎，原始值用于持久化。
enum SpeechEngine: String, CaseIterable, Identifiable {
    case system
    case phonon

    var id: String {
        rawValue
    }

    /// 设置页展示的中文名称。
    var title: String {
        switch self {
        case .system:
            return "系统语音"
        case .phonon:
            return "Phonon（实验）"
        }
    }
}
