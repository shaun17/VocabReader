import SwiftUI

struct BookmarkListView: View {
    @ObservedObject var store: BookmarkStore
    let translator: ArticleParagraphTranslatorProtocol

    @State private var expandedWordID: UUID?
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        Group {
            if store.bookmarks.isEmpty {
                ContentUnavailableView(
                    "暂无收藏",
                    systemImage: "star",
                    description: Text("在阅读文章时长按选中单词，点击\"收藏\"即可添加")
                )
            } else {
                // 不用 List：List 的单元格会瞬间改成新高度、内容在格子里居中，
                // 和 SwiftUI 的展开动画不同步，卡片会先跳一下再滑回来。ScrollView 里布局全由 SwiftUI 动画驱动。
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(groupedByDate, id: \.date) { group in
                            Section {
                                ForEach(group.words) { word in
                                    BookmarkRow(
                                        word: word,
                                        isExpanded: expandedWordID == word.id,
                                        animation: expandAnimation,
                                        translator: translator,
                                        onToggle: {
                                            toggleExpandedWord(word.id)
                                        },
                                        onDelete: {
                                            removeBookmark(word.id)
                                        }
                                    )
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            removeBookmark(word.id)
                                        } label: {
                                            Label("删除", systemImage: "trash")
                                        }
                                    }
                                    .transition(.opacity)
                                }
                            } header: {
                                BookmarkSectionHeader(dateLabel: group.dateLabel)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
        }
        .background { LinedPaperBackground() }
        .navigationTitle("收藏单词")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var groupedByDate: [DateGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: store.bookmarks) { word in
            calendar.startOfDay(for: word.bookmarkedAt)
        }
        return grouped
            .map { DateGroup(date: $0.key, words: $0.value) }
            .sorted { $0.date > $1.date }
    }

    private var expandAnimation: Animation? {
        accessibilityReduceMotion ? nil : .easeInOut(duration: 0.26)
    }

    private func toggleExpandedWord(_ wordID: UUID) {
        withAnimation(expandAnimation) {
            expandedWordID = expandedWordID == wordID ? nil : wordID
        }
    }

    /// 删除入口：长按卡片的菜单，或展开后操作栏右侧的垃圾桶。
    private func removeBookmark(_ wordID: UUID) {
        withAnimation(expandAnimation) {
            store.remove(id: wordID)
            if expandedWordID == wordID {
                expandedWordID = nil
            }
        }
    }
}

private struct DateGroup {
    let date: Date
    let words: [BookmarkedWord]

    var dateLabel: String {
        date.formatted(.dateTime.year().month().day())
    }
}

private struct BookmarkRow: View {
    let word: BookmarkedWord
    let isExpanded: Bool
    let animation: Animation?
    let onToggle: () -> Void
    let onDelete: () -> Void

    @StateObject private var supplementViewModel: ArticleParagraphTranslationViewModel

    /// 每个收藏行复用文章段落的翻译/解析状态机，并把收藏例句作为请求上下文。
    init(
        word: BookmarkedWord,
        isExpanded: Bool,
        animation: Animation?,
        translator: ArticleParagraphTranslatorProtocol,
        onToggle: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.word = word
        self.isExpanded = isExpanded
        self.animation = animation
        self.onToggle = onToggle
        self.onDelete = onDelete
        _supplementViewModel = StateObject(
            wrappedValue: ArticleParagraphTranslationViewModel(
                paragraph: word.sentence,
                translator: translator
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(word.spelling)
                            .font(.system(.headline, design: .serif).italic())
                            .foregroundStyle(Color.readingTitle)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.readingTextTertiary)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }

                    ExpandableSentence(text: word.sentence, isExpanded: isExpanded, animation: animation)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "收起 \(word.spelling)" : "展开 \(word.spelling)")

            // 展开区始终在布局里，只由抽屉裁切高度：收起时按钮随抽屉一起被裁掉，不会淡出残留在下一张卡片上。
            SupplementDrawer(isOpen: isExpanded, animation: animation) {
                VStack(alignment: .leading, spacing: 8) {
                    Rectangle()
                        .fill(Color.readingRule)
                        .frame(height: 1)

                    HStack(spacing: ReadingSupplementActionMetrics.groupSpacing) {
                        ReadingSupplementActionButton(
                            presentation: supplementPresentation(for: .translation)
                        ) {
                            Task {
                                await supplementViewModel.didTapTranslateButton()
                            }
                        }

                        ReadingSupplementActionButton(
                            presentation: supplementPresentation(for: .analysis)
                        ) {
                            Task {
                                await supplementViewModel.didTapAnalyzeButton()
                            }
                        }

                        Spacer(minLength: 0)

                        Button(role: .destructive, action: onDelete) {
                            Image(systemName: "trash")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.readingTextTertiary)
                                .frame(width: 36, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("删除 \(word.spelling)")
                    }

                    supplementContent
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ReadingCardBackground(seed: SketchSeed.make(word.id))
        }
    }

    /// 将收藏页状态映射到全局统一的阅读辅助按钮展示模型。
    private func supplementPresentation(for action: ReadingSupplementAction) -> ReadingSupplementActionPresentation {
        let panel: ArticleParagraphExpansionPanel = action == .translation ? .translation : .analysis
        let isLoading = supplementViewModel.loadingPanel == panel
        return ReadingSupplementActionPresentation(
            action: action,
            isActive: supplementViewModel.expandedPanel == panel || isLoading,
            isLoading: isLoading,
            isDisabled: supplementViewModel.isLoading
        )
    }

    @ViewBuilder
    private var supplementContent: some View {
        if supplementViewModel.isLoading {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(supplementViewModel.loadingPanel == .translation ? "翻译中…" : "解析中…")
                    .font(.footnote)
                    .foregroundStyle(Color.readingTextSecondary)
            }
            .padding(.top, 2)
        } else if let text = expandedSupplementText {
            Text(text)
                .font(.footnote)
                .foregroundStyle(Color.readingTextSecondary)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.readingControlFill)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else if let error = supplementViewModel.error {
            Label(error, systemImage: "exclamationmark.circle")
                .font(.footnote)
                .foregroundStyle(Color.readingError)
        }
    }

    private var expandedSupplementText: String? {
        switch supplementViewModel.expandedPanel {
        case .translation:
            return supplementViewModel.translation
        case .analysis:
            return supplementViewModel.analysis
        case nil:
            return nil
        }
    }
}

/// 例句的收起 / 展开：完整句子始终按全高排版，外框在“一行高”和“全高”之间动画并裁切，
/// 上面叠一层单行省略版本做交叉淡入淡出。避免直接切换 lineLimit 导致文字瞬间回流、卡片跳一下。
private struct ExpandableSentence: View {
    let text: String
    let isExpanded: Bool
    let animation: Animation?

    @State private var collapsedHeight: CGFloat?
    @State private var expandedHeight: CGFloat?

    private let font = Font.system(.subheadline, design: .serif)

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text(text)
                .font(font)
                .foregroundStyle(Color.readingTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { expandedHeight = $0 }
                .opacity(isExpanded ? 1 : 0)

            Text(text)
                .font(font)
                .foregroundStyle(Color.readingTextSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { collapsedHeight = $0 }
                .opacity(isExpanded ? 0 : 1)
                .accessibilityHidden(true)
        }
        .frame(height: isExpanded ? expandedHeight : collapsedHeight, alignment: .top)
        .clipped()
        .animation(animation, value: isExpanded)
    }
}

private struct BookmarkSectionHeader: View {
    let dateLabel: String

    var body: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(Color.readingTitle.opacity(0.22))
                .frame(width: 18, height: 6)

            Text(dateLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.readingTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.top, 8)
    }
}
