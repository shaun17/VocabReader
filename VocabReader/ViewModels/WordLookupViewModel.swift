import AVFoundation
import Foundation

/// 一次查词请求；每次点击生成新 id，同一个词连点也会重新弹出。
struct WordLookupRequest: Identifiable, Equatable {
    let id = UUID()
    /// 点击的单词或长按选中的片段。
    let text: String
    /// 所在原句，用于文中释义和原句翻译。
    let sentence: String
    /// 是否为今日目标词。
    var isTargetWord = false
}

@MainActor
final class WordLookupViewModel: ObservableObject {
    enum DetailState: Equatable {
        case loading
        case loaded(WordLookupResult)
        case failed(String)
    }

    @Published private(set) var detail: DetailState = .loading
    /// 设备端翻译先到的快速译文：LLM 词条到达前先顶上，词条失败时也保留。
    @Published private(set) var quickMeaning: String?
    @Published private(set) var quickSentenceTranslation: String?
    @Published private(set) var isSpeaking = false

    let request: WordLookupRequest
    private let service: WordLookupServiceProtocol
    private let pronouncer = WordPronouncer()

    init(request: WordLookupRequest, service: WordLookupServiceProtocol) {
        self.request = request
        self.service = service
        pronouncer.onFinish = { [weak self] in
            self?.isSpeaking = false
        }
    }

    var result: WordLookupResult? {
        if case .loaded(let result) = detail { return result }
        return nil
    }

    var isLoading: Bool { detail == .loading }

    var failureMessage: String? {
        if case .failed(let message) = detail { return message }
        return nil
    }

    /// 文中释义：优先 LLM 词条，其次设备端快速译文。
    var contextMeaning: String? {
        result?.contextMeaning.nonEmpty ?? quickMeaning
    }

    var sentenceTranslation: String? {
        result?.sentenceTranslation.nonEmpty ?? quickSentenceTranslation
    }

    func load() async {
        detail = .loading
        do {
            let result = try await service.lookUp(word: request.text, sentence: request.sentence)
            detail = .loaded(result)
        } catch is CancellationError {
            return
        } catch {
            detail = .failed(error.localizedDescription)
        }
    }

    func applyQuickTranslation(meaning: String?, sentence: String?) {
        quickMeaning = meaning?.nonEmpty
        quickSentenceTranslation = sentence?.nonEmpty
    }

    /// - Parameter keepsAudioSession: 文章朗读进行中时不交还音频会话，避免打断正文播放。
    func pronounce(keepsAudioSession: Bool) {
        // 正在读时再点就是停止，避免取消回调和新一次朗读的状态互相覆盖。
        guard !isSpeaking else {
            stopSpeaking()
            return
        }
        isSpeaking = true
        pronouncer.speak(request.text, keepsAudioSession: keepsAudioSession)
    }

    func stopSpeaking() {
        pronouncer.stop()
        isSpeaking = false
    }
}

/// 单词发音：独立的合成器，不干扰文章朗读的进度和回调。
private final class WordPronouncer: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var keepsAudioSession = false
    var onFinish: (@MainActor () -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, keepsAudioSession: Bool) {
        self.keepsAudioSession = keepsAudioSession
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.42
        AudioSessionManager.activate()
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finish()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finish()
    }

    private func finish() {
        if !keepsAudioSession {
            AudioSessionManager.deactivate()
        }
        let onFinish = onFinish
        Task { @MainActor in onFinish?() }
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
