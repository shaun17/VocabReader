import SwiftUI

/// 设置选项按等宽列排布，行与行左右对齐；列数由最宽选项决定并随可用宽度自适应（折叠屏展开后会自动变多）。
/// 选项少于一行时不拉伸单元格，避免出现大块胶囊。
struct SettingsChoiceGrid: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 0

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let grid = gridMetrics(for: subviews, within: proposal.width)
        let rowCount = (subviews.count + grid.columns - 1) / grid.columns
        let height = CGFloat(rowCount) * grid.rowHeight + CGFloat(rowCount - 1) * verticalSpacing
        return CGSize(width: proposal.width ?? grid.contentWidth, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard !subviews.isEmpty else { return }
        let grid = gridMetrics(for: subviews, within: bounds.width)
        let cellProposal = ProposedViewSize(width: grid.cellWidth, height: grid.rowHeight)

        for (index, subview) in subviews.enumerated() {
            let column = index % grid.columns
            let row = index / grid.columns
            subview.place(
                at: CGPoint(
                    x: bounds.minX + CGFloat(column) * (grid.cellWidth + horizontalSpacing),
                    y: bounds.minY + CGFloat(row) * (grid.rowHeight + verticalSpacing)
                ),
                anchor: .topLeading,
                proposal: cellProposal
            )
        }
    }

    /// 测量与放置共用同一套列宽计算，避免动态字号下两次结果不一致。
    private func gridMetrics(for subviews: Subviews, within proposedWidth: CGFloat?) -> GridMetrics {
        let idealSizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let widestItem = max(SettingsChoiceButtonMetrics.minimumCellWidth, idealSizes.map(\.width).max() ?? 0)
        let rowHeight = idealSizes.map(\.height).max() ?? 0

        guard let availableWidth = proposedWidth, availableWidth.isFinite else {
            let contentWidth = CGFloat(subviews.count) * widestItem + CGFloat(subviews.count - 1) * horizontalSpacing
            return GridMetrics(columns: subviews.count, cellWidth: widestItem, rowHeight: rowHeight, contentWidth: contentWidth)
        }

        let columns = max(1, Int((availableWidth + horizontalSpacing) / (widestItem + horizontalSpacing)))
        let cellWidth = (availableWidth - CGFloat(columns - 1) * horizontalSpacing) / CGFloat(columns)
        return GridMetrics(columns: columns, cellWidth: cellWidth, rowHeight: rowHeight, contentWidth: availableWidth)
    }
}

private struct GridMetrics {
    let columns: Int
    let cellWidth: CGFloat
    let rowHeight: CGFloat
    let contentWidth: CGFloat
}
