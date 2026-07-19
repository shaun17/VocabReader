import SwiftUI

/// 设置选项按自身宽度从左向右排列，空间不足时自然换行，避免等宽网格制造大块空白热区。
struct SettingsChoiceFlowLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    /// 使用父视图提供的可用宽度测量换行后的整体高度。
    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let result = layoutSubviews(subviews, within: proposal.width)
        return CGSize(
            width: proposal.width ?? result.contentWidth,
            height: result.contentHeight
        )
    }

    /// 按测量阶段得到的左上角坐标放置每个选项，始终保持左对齐。
    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = layoutSubviews(subviews, within: bounds.width)
        for (index, subview) in subviews.enumerated() {
            let offset = result.offsets[index]
            subview.place(
                at: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y),
                anchor: .topLeading,
                proposal: .unspecified
            )
        }
    }

    /// 统一计算测量与放置所需的坐标，确保动态字号变化时不会出现两套换行结果。
    private func layoutSubviews(_ subviews: Subviews, within proposedWidth: CGFloat?) -> LayoutResult {
        let availableWidth = max(0, proposedWidth ?? .greatestFiniteMagnitude)
        var offsets: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var contentWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > 0, currentX + size.width > availableWidth {
                currentX = 0
                currentY += rowHeight + verticalSpacing
                rowHeight = 0
            }

            offsets.append(CGPoint(x: currentX, y: currentY))
            contentWidth = max(contentWidth, currentX + size.width)
            currentX += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }

        let contentHeight = subviews.isEmpty ? 0 : currentY + rowHeight
        return LayoutResult(
            offsets: offsets,
            contentWidth: contentWidth,
            contentHeight: contentHeight
        )
    }
}

private struct LayoutResult {
    let offsets: [CGPoint]
    let contentWidth: CGFloat
    let contentHeight: CGFloat
}
