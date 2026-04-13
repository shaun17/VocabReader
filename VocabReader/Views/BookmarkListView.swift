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
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation {
                                        expandedWordID = expandedWordID == word.id ? nil : word.id
                                    }
                                }
                            }
                            .onDelete { offsets in
                                let wordsToDelete = offsets.map { group.words[$0] }
                                for word in wordsToDelete {
                                    store.remove(id: word.id)
                                }
                            }
                        } header: {
                            Text(group.dateLabel)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(word.spelling)
                .font(.system(.body, design: .serif))
                .fontWeight(.medium)

            if isExpanded {
                Text(word.sentence)
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(.secondary)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
    }
}
