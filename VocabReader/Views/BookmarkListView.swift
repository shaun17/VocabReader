import SwiftUI

struct BookmarkListView: View {
    @ObservedObject var store: BookmarkStore

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
                                    isExpanded: expandedWordID == word.id
                                )
                                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    toggleExpandedWord(word.id)
                                }
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
    private let expansionAnimation = Animation.easeInOut(duration: 0.18)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(word.spelling)
                    .font(.system(.headline, design: .serif).italic())
                    .foregroundStyle(Color.readingTitle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            Text(word.sentence)
                .font(.system(.body, design: .serif))
                .foregroundStyle(isExpanded ? .primary : .secondary)
                .lineLimit(isExpanded ? nil : 1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                // 句子区域始终存在，折叠时只保留一行摘要，避免条件插入/移除导致单词跟着跳动。
                .animation(expansionAnimation, value: isExpanded)

            Text(isExpanded ? "点击收起例句" : "点击展开例句")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ReadingCardBackground()
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
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .textCase(nil)
    }
}
