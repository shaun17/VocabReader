import SwiftUI

struct BookmarkListView: View {
    @ObservedObject var store: BookmarkStore
    let translator: ArticleParagraphTranslatorProtocol

    @State private var expandedWordID: UUID?

    var body: some View {
        Group {
            if store.bookmarks.isEmpty {
                ContentUnavailableView(
                    "暂无收藏",
                    systemImage: "star",
                    description: Text("在阅读文章时长按选中单词，点击\"收藏\"即可添加")
                )
            } else {
                List {
                    ForEach(groupedByDate, id: \.date) { group in
                        Section {
                            ForEach(group.words) { word in
                                BookmarkRow(
                                    word: word,
                                    isExpanded: expandedWordID == word.id,
                                    translator: translator,
                                    onToggle: {
                                        toggleExpandedWord(word.id)
                                    }
                                )
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        removeBookmark(word.id)
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                            }
                        } header: {
                            BookmarkSectionHeader(dateLabel: group.dateLabel)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
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

    /// 收藏行只做轻量动画切换，避免 `List` 在位移过渡下出现明显抖动。
    private func toggleExpandedWord(_ wordID: UUID) {
        expandedWordID = expandedWordID == wordID ? nil : wordID
    }

    /// 收藏页改用自定义卡片后，删除动作通过侧滑按钮处理，保持交互能力不回退。
    private func removeBookmark(_ wordID: UUID) {
        store.remove(id: wordID)
        if expandedWordID == wordID {
            expandedWordID = nil
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
    let onToggle: () -> Void

    @StateObject private var supplementViewModel: ArticleParagraphTranslationViewModel
    private let expansionAnimation = Animation.easeInOut(duration: 0.18)

    /// 每个收藏行复用文章段落的翻译/解析状态机，并把收藏例句作为请求上下文。
    init(
        word: BookmarkedWord,
        isExpanded: Bool,
        translator: ArticleParagraphTranslatorProtocol,
        onToggle: @escaping () -> Void
    ) {
        self.word = word
        self.isExpanded = isExpanded
        self.onToggle = onToggle
        _supplementViewModel = StateObject(
            wrappedValue: ArticleParagraphTranslationViewModel(
                paragraph: word.sentence,
                translator: translator
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onToggle) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(word.spelling)
                            .font(.system(.headline, design: .serif).italic())
                            .foregroundStyle(Color.readingTitle)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.readingTextTertiary)
                    }

                    Text(word.sentence)
                        .font(.system(.subheadline, design: .serif))
                        .foregroundStyle(
                            isExpanded ? Color.readingTextPrimary : Color.readingTextSecondary
                        )
                        .lineLimit(isExpanded ? nil : 1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "收起 \(word.spelling)" : "展开 \(word.spelling)")

            if isExpanded {
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
                }

                supplementContent
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ReadingCardBackground()
        }
        .animation(expansionAnimation, value: isExpanded)
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
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .textCase(nil)
    }
}
