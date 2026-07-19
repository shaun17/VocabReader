import SwiftUI
import UIKit
import XCTest
@testable import VocabReader

@MainActor
final class AppAppearanceWindowBridgeTests: XCTestCase {
    /// 已呈现的设置弹窗从手动主题切回系统时，必须原地恢复系统外观且不能重建内容。
    func testPresentedSettingsReturnsToSystemAppearanceWithoutRecreation() async {
        guard let windowScene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            XCTFail("测试宿主缺少可用窗口场景")
            return
        }

        let systemStyle = resolvedSystemStyle(from: windowScene)
        let systemScheme: ColorScheme = systemStyle == .dark ? .dark : .light
        let manualAppearance: AppAppearance = systemStyle == .dark ? .light : .dark
        let manualScheme: ColorScheme = manualAppearance == .dark ? .dark : .light
        let appearanceState = WindowAppearanceTestState(appearance: manualAppearance)
        let rootController = UIHostingController(
            rootView: WindowAppearanceTestHarness(appearanceState: appearanceState)
        )
        let previousKeyWindow = windowScene.windows.first(where: \.isKeyWindow)
        let testWindow = UIWindow(windowScene: windowScene)
        testWindow.rootViewController = rootController
        testWindow.makeKeyAndVisible()
        defer {
            rootController.dismiss(animated: false)
            testWindow.isHidden = true
            previousKeyWindow?.makeKeyAndVisible()
        }

        let manualExpectation = expectation(description: "设置页显示手动主题")
        let systemExpectation = expectation(description: "设置页恢复系统主题")
        var didRequestSystem = false
        var appearanceCount = 0
        var didObserveManual = false
        var didObserveSystem = false
        let settingsController = UIHostingController(
            rootView: SettingsColorSchemeProbe(
                onAppear: {
                    appearanceCount += 1
                },
                onResolve: { colorScheme in
                    if colorScheme == manualScheme, !didObserveManual {
                        didObserveManual = true
                        manualExpectation.fulfill()
                    }
                    if didRequestSystem, colorScheme == systemScheme, !didObserveSystem {
                        didObserveSystem = true
                        systemExpectation.fulfill()
                    }
                }
            )
        )
        settingsController.modalPresentationStyle = .pageSheet
        rootController.present(settingsController, animated: false)

        await fulfillment(of: [manualExpectation], timeout: 1)
        XCTAssertEqual(testWindow.overrideUserInterfaceStyle, manualAppearance.userInterfaceStyle)
        didRequestSystem = true
        appearanceState.appearance = .system
        await fulfillment(of: [systemExpectation], timeout: 1)

        XCTAssertEqual(testWindow.overrideUserInterfaceStyle, .unspecified)
        XCTAssertEqual(settingsController.traitCollection.userInterfaceStyle, systemStyle)
        XCTAssertEqual(appearanceCount, 1, "切换主题不应通过重建设置页实现")
    }

    /// 从场景读取设备当前明暗模式，并把未解析状态稳定归为浅色。
    private func resolvedSystemStyle(from windowScene: UIWindowScene) -> UIUserInterfaceStyle {
        windowScene.traitCollection.userInterfaceStyle == .dark ? .dark : .light
    }
}

@MainActor
private final class WindowAppearanceTestState: ObservableObject {
    @Published var appearance: AppAppearance

    /// 保存测试中的可变外观，驱动同一个窗口桥接器更新。
    init(appearance: AppAppearance) {
        self.appearance = appearance
    }
}

private struct WindowAppearanceTestHarness: View {
    @ObservedObject var appearanceState: WindowAppearanceTestState

    var body: some View {
        Color.clear
            .background {
                AppAppearanceWindowBridge(appearance: appearanceState.appearance)
            }
    }
}

private struct SettingsColorSchemeProbe: View {
    @Environment(\.colorScheme) private var colorScheme
    let onAppear: () -> Void
    let onResolve: (ColorScheme) -> Void

    var body: some View {
        NavigationStack {
            Color.clear
                .onAppear {
                    onAppear()
                    onResolve(colorScheme)
                }
                .onChange(of: colorScheme) { _, newColorScheme in
                    onResolve(newColorScheme)
                }
        }
    }
}
