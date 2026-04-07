import SwiftUI

struct WordDetailSheet: View {
    let word: VocabWord
    let maiMemo: MaiMemoServiceProtocol

    @State private var definition: String?
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(word.spelling)
                .font(.title2.bold())

            if isLoading {
                ProgressView()
            } else if let definition {
                Text(definition)
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                Text("暂无释义")
                    .font(.body)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            definition = try? await maiMemo.fetchDefinition(vocId: word.id)
            isLoading = false
        }
    }
}
