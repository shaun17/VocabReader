import SwiftUI

@MainActor
final class TodayViewModel: ObservableObject {
    @Published var articles: [Article] = []
    @Published var isLoading = false
    @Published var error: String?

    private let generator: ArticleGenerator

    init(generator: ArticleGenerator) {
        self.generator = generator
    }

    func loadArticles() async {
        isLoading = true
        error = nil
        do {
            articles = try await generator.generateTodayArticles()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

struct TodayView: View {
    @StateObject private var viewModel: TodayViewModel
    @State private var showSettings = false
    @State private var selectedArticle: Article?

    init(generator: ArticleGenerator) {
        _viewModel = StateObject(wrappedValue: TodayViewModel(generator: generator))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("正在生成今日文章…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.error {
                    ContentUnavailableView(
                        "加载失败",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else if viewModel.articles.isEmpty {
                    ContentUnavailableView(
                        "暂无今日单词",
                        systemImage: "book.closed",
                        description: Text("请先在墨墨 App 中完成今日初始化")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.articles) { article in
                                ArticleCardView(article: article)
                                    .onTapGesture {
                                        selectedArticle = article
                                    }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("今日阅读")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(settings: SettingsStore.shared)
            }
            .navigationDestination(item: $selectedArticle) { article in
                ArticleReaderView(article: article,
                                  maiMemo: MaiMemoService(token: SettingsStore.shared.maiMemoToken))
            }
        }
        .task {
            await viewModel.loadArticles()
        }
    }
}
