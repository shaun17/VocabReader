import UIKit

/// 用户可选择的应用外观；`system` 会清除窗口覆盖，因此默认跟随设备设置。
enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    /// 使用稳定原始值作为设置页列表标识和持久化值。
    var id: String {
        rawValue
    }

    /// 设置页展示的中文名称。
    var title: String {
        switch self {
        case .system:
            return "跟随系统"
        case .light:
            return "浅色"
        case .dark:
            return "深色"
        }
    }

    /// 设置页用于快速区分三种外观的系统图标。
    var systemImage: String {
        switch self {
        case .system:
            return "circle.lefthalf.filled"
        case .light:
            return "sun.max.fill"
        case .dark:
            return "moon.stars.fill"
        }
    }

    /// 将用户偏好映射为窗口外观；`.unspecified` 会主动恢复系统主题。
    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system:
            return .unspecified
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}
