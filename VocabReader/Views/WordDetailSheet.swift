import SwiftUI

struct WordDetailSheet: View {
    let word: VocabWord
    let translation: String?
    let isLoading: Bool
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(word.spelling)
                .font(.title2.bold())

            if isLoading {
                ProgressView()
            } else if let translation {
                Text(translation)
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else if let error {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background { LinedPaperBackground() }
    }
}
