import SwiftUI

@MainActor
final class TodayViewModel: ObservableObject {
    @Published var articles: [Article] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var error: String?

    private let generatorFactory: @MainActor () -> TodayArticleGenerating
    private var pagingSession: TodayArticlePagingSession?
    private var hasMoreArticles = true
    private var isLoadMoreFooterVisible = false
    private var inFlightArticleRequest: Task<Article?, Error>?

    init(generatorFactory: @escaping @MainActor () -> TodayArticleGenerating = TodayViewModel.makeDefaultGenerator) {
        self.generatorFactory = generatorFactory
    }

    /// 当前已生成文章覆盖的目标词数量，用于和设置里的今日总词数对齐展示。
    var coveredWordCount: Int {
        articles.reduce(into: 0) { partialResult, article in
            partialResult += article.targetWords.count
        }
    }

    func loadArticles() async {
        await reloadArticles(force: false)
    }

    func regenerateArticles() async {
        await reloadArticles(force: true)
    }

    /// 保存设置后同步分页参数，不触发重载。主题或体裁变更时更新后续生成的 session。
    func syncPaginationSettingsAfterSave(
        previousSettings: ArticleGenerationSettings,
        newSettings: ArticleGenerationSettings
    ) async {
        guard previousSettings != newSettings else { return }
        guard !articles.isEmpty else { return }

        let consumedWordCount = articles.reduce(into: 0) { partialResult, article in
            partialResult += article.targetWords.count
        }
        let newSession = generatorFactory().makePagingSession(startingAtConsumedWordCount: consumedWordCount)
        pagingSession = newSession
        error = nil
        hasMoreArticles = consumedWordCount < newSettings.articleWordCount
    }

    private func reloadArticles(force: Bool) async {
        guard !isLoading else { return }
        guard inFlightArticleRequest == nil else { return }
        if !force, !articles.isEmpty {
            return
        }

        isLoading = true
        error = nil
        articles = []
        hasMoreArticles = true
        isLoadMoreFooterVisible = false
        pagingSession = generatorFactory().makePagingSession()
        defer { isLoading = false }

        for _ in 0..<3 {
            guard hasMoreArticles else { break }
            await loadNextArticle()
        }
    }

    var shouldShowLoadMoreFooter: Bool {
        !articles.isEmpty && hasMoreArticles
    }

    func setLoadMoreFooterVisible(_ isVisible: Bool) {
        isLoadMoreFooterVisible = isVisible
    }

    func loadMoreIfNeededForListTail() async {
        guard isLoadMoreFooterVisible else { return }
        guard hasMoreArticles else { return }
        guard !isLoading && !isLoadingMore else { return }
        guard inFlightArticleRequest == nil else { return }
        guard articles.last != nil else { return }

        error = nil
        isLoadingMore = true
        defer { isLoadingMore = false }

        await loadNextArticle()
    }

    private static func makeDefaultGenerator() -> TodayArticleGenerating {
        let settings = SettingsStore.shared
        let maiMemo = MaiMemoService(token: settings.maiMemoToken)
        let llm = LLMService(config: settings.llmConfig)
        return ArticleGenerator(
            maiMemo: maiMemo,
            llm: llm,
            batchSize: settings.wordsPerArticle,
            todayWordLimit: settings.articleWordCount,
            scenes: settings.enabledScenes,
            topic: settings.selectedTopic
        )
    }

    private func loadNextArticle() async {
        guard let pagingSession else { return }
        guard inFlightArticleRequest == nil else { return }

        let requestTask = Task {
            try await pagingSession.loadNextArticle()
        }
        inFlightArticleRequest = requestTask

        do {
            defer { inFlightArticleRequest = nil }

            guard let article = try await requestTask.value else {
                hasMoreArticles = false
                return
            }

            articles.append(article)
            error = nil
        } catch {
            self.error = error.localizedDescription
            hasMoreArticles = true
        }
    }
}

struct TodayView: View {
    @StateObject private var viewModel = TodayViewModel()
    @ObservedObject private var settings = SettingsStore.shared
    @State private var showSettings = false
    @State private var selectedArticle: Article?
    @State private var settingsSnapshot = SettingsStore.shared.articleGenerationSettings
    @StateObject private var bookmarkStore = BookmarkStore.shared
    @State private var showBookmarks = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.articles.isEmpty && viewModel.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("正在生成第一篇文章…")
                            .foregroundStyle(Color.readingTextSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.error, viewModel.articles.isEmpty {
                    ContentUnavailableView(
                        "生成失败",
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
                        LazyVStack(spacing: 20) {
                            TodayVocabularyProgressView(
                                coveredWordCount: viewModel.coveredWordCount,
                                targetWordCount: settings.articleWordCount
                            )

                            if let error = viewModel.error {
                                Text(error)
                                    .font(.footnote)
                                    .foregroundStyle(Color.readingError)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            ForEach(viewModel.articles) { article in
                                ArticleCardView(article: article)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedArticle = article
                                    }
                            }

                            if viewModel.isLoading || viewModel.shouldShowLoadMoreFooter {
                                VStack(spacing: 8) {
                                    if viewModel.isLoading || viewModel.isLoadingMore {
                                        ProgressView()
                                        Text("正在生成文章…")
                                            .font(.footnote)
                                            .foregroundStyle(Color.readingTextSecondary)
                                    } else {
                                        Text("继续下滑生成更多")
                                            .font(.footnote)
                                            .foregroundStyle(Color.readingTextTertiary)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .onAppear {
                                    viewModel.setLoadMoreFooterVisible(true)
                                }
                                .onDisappear {
                                    viewModel.setLoadMoreFooterVisible(false)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 1)
                            .onEnded { _ in
                                Task {
                                    await viewModel.loadMoreIfNeededForListTail()
                                }
                            }
                    )
                }
            }
            .background { LinedPaperBackground() }
            .scrollContentBackground(.hidden)
            .navigationTitle("今日阅读")
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        showBookmarks = true
                    } label: {
                        Image(systemName: "star")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await viewModel.regenerateArticles()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }

                    Button {
                        settingsSnapshot = SettingsStore.shared.articleGenerationSettings
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(settings: SettingsStore.shared) {
                    Task {
                        await viewModel.syncPaginationSettingsAfterSave(
                            previousSettings: settingsSnapshot,
                            newSettings: SettingsStore.shared.articleGenerationSettings
                        )
                    }
                }
            }
            .navigationDestination(item: $selectedArticle) { article in
                let translationService = WordTranslatorService(config: SettingsStore.shared.llmConfig)
                ArticleReaderView(
                    article: article,
                    translator: translationService,
                    paragraphTranslator: translationService
                )
            }
            .navigationDestination(isPresented: $showBookmarks) {
                let translationService = WordTranslatorService(config: SettingsStore.shared.llmConfig)
                BookmarkListView(
                    store: bookmarkStore,
                    translator: translationService
                )
            }
        }
        .task {
            await viewModel.loadArticles()
        }
    }
}

private struct TodayVocabularyProgressView: View {
    let coveredWordCount: Int
    let targetWordCount: Int

    private var normalizedTarget: Int {
        max(targetWordCount, 1)
    }

    private var displayedCoveredCount: Int {
        min(coveredWordCount, normalizedTarget)
    }

    private var progressValue: Double {
        Double(displayedCoveredCount) / Double(normalizedTarget)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("今日词汇")
                    .font(.system(.subheadline, design: .serif).weight(.semibold))
                    .foregroundStyle(Color.readingTextPrimary)

                Spacer()

                Text("\(displayedCoveredCount)/\(normalizedTarget)")
                    .font(.system(.footnote, design: .serif).weight(.semibold))
                    .foregroundStyle(Color.readingTitle)
            }

            // 显示今日目标词汇覆盖进度，避免拆分成多篇后误以为设置未生效。
            ProgressView(value: progressValue)
                .tint(Color.readingTitle)
        }
        .padding(.top, 4)
    }
}
