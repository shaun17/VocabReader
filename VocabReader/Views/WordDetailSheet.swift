import SwiftUI

struct WordDetailSheet: View {
    let word: VocabWord
    @StateObject private var viewModel: WordDetailViewModel

    init(word: VocabWord, translator: WordTranslatorServiceProtocol) {
        self.word = word
        _viewModel = StateObject(wrappedValue: WordDetailViewModel(word: word, translator: translator))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(word.spelling)
                .font(.title2.bold())

            if viewModel.isLoading {
                ProgressView()
            } else if let translation = viewModel.translation {
                Text(translation)
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else if let error = viewModel.error {
                Text(error)
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                Text("暂无翻译")
                    .font(.body)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            await viewModel.loadTranslation()
        }
    }
}
