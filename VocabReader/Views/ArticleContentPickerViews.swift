import SwiftUI

/// 文章主题二级页：按生活 / 人文 / 专业分组，单选，选中后直接返回设置页。
struct ArticleTopicPickerView: View {
    @Binding var selection: ArticleTopic
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ArticleContentPickerPage(title: "文章主题") {
            ForEach(ArticleTopicGroup.allCases) { group in
                SettingsFieldLabel(group.rawValue)
                    .padding(.horizontal, 4)
                    .padding(.top, group == ArticleTopicGroup.allCases.first ? 0 : 10)

                ArticleContentPickerCard(items: group.topics) { topic in
                    ArticleContentPickerRow(
                        systemImage: topic.systemImageName,
                        title: topic.rawValue,
                        summary: topic.summary,
                        isSelected: selection == topic,
                        indicator: .checkmark
                    ) {
                        selection = topic
                        dismiss()
                    }
                }
            }
        }
    }
}

/// 文章体裁二级页：多选，至少保留一种；生成时在已选体裁中轮换。
struct ArticleScenePickerView: View {
    @Binding var draft: SettingsDraft

    var body: some View {
        ArticleContentPickerPage(title: "文章体裁") {
            SettingsHint("至少保留一种体裁，生成时会在已选体裁中轮换")
                .padding(.horizontal, 4)

            ArticleContentPickerCard(items: ArticleScene.allCases) { scene in
                let isEnabled = draft.isSceneEnabled(scene)
                ArticleContentPickerRow(
                    systemImage: scene.systemImageName,
                    title: scene.rawValue,
                    summary: scene.summary,
                    isSelected: isEnabled,
                    indicator: .toggle
                ) {
                    draft.setSceneEnabled(!isEnabled, for: scene)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("全选") {
                    draft.enabledScenes = ArticleScene.allCases
                }
                .disabled(draft.enabledScenes.count == ArticleScene.allCases.count)
            }
        }
    }
}

extension ArticleScene {
    /// 设置页一行内展示已选体裁：全选、少量时列名字，其余显示数量。
    static func selectionSummary(_ scenes: [ArticleScene]) -> String {
        if scenes.count == allCases.count {
            return "全部 \(allCases.count) 种"
        }
        if scenes.count <= 2 {
            return scenes.map(\.rawValue).joined(separator: "、")
        }
        return "已选 \(scenes.count) 种"
    }
}

// MARK: - Shared building blocks

private struct ArticleContentPickerPage<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            LinedPaperBackground()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    content
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ArticleContentPickerCard<Item: Identifiable & Equatable, Row: View>: View {
    let items: [Item]
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                row(item)

                if item != items.last {
                    SettingsDivider()
                }
            }
        }
        .padding(.horizontal, 16)
        .settingsCardBackground()
    }
}

private struct ArticleContentPickerRow: View {
    enum Indicator {
        case checkmark
        case toggle
    }

    let systemImage: String
    let title: String
    let summary: String
    let isSelected: Bool
    let indicator: Indicator
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.body)
                    .foregroundStyle(Color.readingTitle)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.readingTextPrimary)

                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(Color.readingTextSecondary)
                }

                Spacer(minLength: 8)

                indicatorImage
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 10)
            .frame(minHeight: SettingsStepperMetrics.minimumTouchSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(SettingsPressButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var indicatorImage: some View {
        switch indicator {
        case .checkmark:
            Image(systemName: "checkmark")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Color.readingTitle)
                .opacity(isSelected ? 1 : 0)
        case .toggle:
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.readingTitle : Color.readingTextTertiary)
        }
    }
}
