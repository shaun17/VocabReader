import SwiftUI
import UIKit

/// 把应用外观统一应用到所属窗口，让主页、弹窗和 UIKit 控件共享同一个主题来源。
struct AppAppearanceWindowBridge: UIViewRepresentable {
    let appearance: AppAppearance

    /// 创建一个透明宿主视图；真正的窗口可能稍后才挂载，因此先保存当前外观。
    func makeUIView(context: Context) -> WindowAppearanceView {
        let view = WindowAppearanceView()
        view.appearance = appearance
        return view
    }

    /// 用户切换主题时更新同一个宿主视图，避免重建设置页或丢失编辑状态。
    func updateUIView(_ uiView: WindowAppearanceView, context: Context) {
        uiView.appearance = appearance
    }
}

/// 负责在进入窗口以及外观变化时同步 `overrideUserInterfaceStyle`。
final class WindowAppearanceView: UIView {
    var appearance: AppAppearance = .system {
        didSet {
            applyAppearanceToWindow()
        }
    }

    /// SwiftUI 创建视图时未必已经有窗口，挂载完成后需要补做一次同步。
    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyAppearanceToWindow()
    }

    /// 显式主题覆盖整个窗口；跟随系统则主动清除已有覆盖。
    private func applyAppearanceToWindow() {
        guard let window else { return }
        let style = appearance.userInterfaceStyle
        guard window.overrideUserInterfaceStyle != style else { return }
        window.overrideUserInterfaceStyle = style
    }
}
