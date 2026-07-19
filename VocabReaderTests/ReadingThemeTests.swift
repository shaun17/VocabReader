import XCTest
import UIKit
@testable import VocabReader

final class ReadingThemeTests: XCTestCase {
    /// 阅读辅助操作必须提供足够大的触控区域，避免后续视觉调整破坏可点击性。
    func testSupplementActionsMeetMinimumTouchTarget() {
        XCTAssertGreaterThanOrEqual(ReadingSupplementActionMetrics.minimumHeight, 44)
    }

    /// 深色阅读背景必须是有暖棕倾向的炭黑，不能退化成纯黑。
    func testDarkReadingBackgroundIsWarmAndNotPureBlack() {
        let background = ReadingPalette.background.resolvedColor(
            with: UITraitCollection(userInterfaceStyle: .dark)
        )
        let components = colorComponents(of: background)

        XCTAssertGreaterThan(components.red, 0)
        XCTAssertGreaterThan(components.red, components.green)
        XCTAssertGreaterThan(components.green, components.blue)
    }

    /// 同一个语义令牌需要随界面外观解析成不同颜色，防止再次写死浅色纸张。
    func testReadingBackgroundAdaptsToColorScheme() {
        let light = ReadingPalette.background.resolvedColor(
            with: UITraitCollection(userInterfaceStyle: .light)
        )
        let dark = ReadingPalette.background.resolvedColor(
            with: UITraitCollection(userInterfaceStyle: .dark)
        )

        XCTAssertNotEqual(light, dark)
    }

    /// 长文主文字在两种阅读背景上都应保持高对比度，同时避免纯黑和纯白。
    func testPrimaryTextHasComfortableContrastInBothAppearances() {
        let lightTraits = UITraitCollection(userInterfaceStyle: .light)
        let darkTraits = UITraitCollection(userInterfaceStyle: .dark)

        let lightContrast = contrastRatio(
            foreground: ReadingPalette.primaryText.resolvedColor(with: lightTraits),
            background: ReadingPalette.background.resolvedColor(with: lightTraits)
        )
        let darkContrast = contrastRatio(
            foreground: ReadingPalette.primaryText.resolvedColor(with: darkTraits),
            background: ReadingPalette.background.resolvedColor(with: darkTraits)
        )

        XCTAssertGreaterThanOrEqual(lightContrast, 7)
        XCTAssertGreaterThanOrEqual(darkContrast, 7)
    }

    /// 强调色按钮上的文字在浅色和深色模式下都要达到普通文字可读标准。
    func testAccentForegroundMaintainsReadableContrast() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let contrast = contrastRatio(
                foreground: ReadingPalette.accentForeground.resolvedColor(with: traits),
                background: ReadingPalette.accent.resolvedColor(with: traits)
            )

            XCTAssertGreaterThanOrEqual(contrast, 4.5)
        }
    }

    /// 提取 sRGB 分量，供色温和对比度断言复用。
    private func colorComponents(of color: UIColor) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            XCTFail("无法读取颜色分量")
            return (0, 0, 0)
        }

        return (red, green, blue)
    }

    /// 按 WCAG 相对亮度公式计算前景与背景的对比度。
    private func contrastRatio(foreground: UIColor, background: UIColor) -> CGFloat {
        let foregroundLuminance = relativeLuminance(of: foreground)
        let backgroundLuminance = relativeLuminance(of: background)
        let lighter = max(foregroundLuminance, backgroundLuminance)
        let darker = min(foregroundLuminance, backgroundLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// 将 sRGB 三通道转换为人眼感知相关的相对亮度。
    private func relativeLuminance(of color: UIColor) -> CGFloat {
        let components = colorComponents(of: color)
        return 0.2126 * linearized(components.red)
            + 0.7152 * linearized(components.green)
            + 0.0722 * linearized(components.blue)
    }

    /// 将经过伽马编码的 sRGB 分量转换到线性空间。
    private func linearized(_ component: CGFloat) -> CGFloat {
        guard component > 0.04045 else { return component / 12.92 }
        return pow((component + 0.055) / 1.055, 2.4)
    }
}
