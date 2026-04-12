import Foundation
import Combine

enum PlaybackState {
    case idle
    case playing
    case paused
}

@MainActor
final class ArticleAudioPlayerViewModel: ObservableObject {
    @Published var playbackState: PlaybackState = .idle
    @Published var currentParagraphIndex: Int?
    @Published var rate: Float = 0.5
    @Published var progress: Double = 0

    private let paragraphs: [ArticleParagraph]
    private let speechService: SpeechServiceProtocol

    /// Incremented on every new speak call; stale callbacks are ignored.
    private var generation: UInt = 0

    private let charOffsets: [Int]
    private let totalChars: Int

    init(paragraphs: [ArticleParagraph], speechService: SpeechServiceProtocol = SpeechService()) {
        self.paragraphs = paragraphs
        self.speechService = speechService

        var offsets: [Int] = []
        var total = 0
        for p in paragraphs {
            offsets.append(total)
            total += p.content.count
        }
        self.charOffsets = offsets
        self.totalChars = max(total, 1)
    }

    func setRate(_ newRate: Float) {
        guard newRate != rate else { return }
        rate = newRate
        guard playbackState == .playing, let index = currentParagraphIndex else { return }
        speechService.stop()
        startPlaying(from: index)
    }

    func togglePlayback() {
        switch playbackState {
        case .idle:
            startPlaying(from: 0)
        case .playing:
            speechService.pause()
            playbackState = .paused
        case .paused:
            speechService.resume()
            playbackState = .playing
        }
    }

    func stop() {
        generation &+= 1
        speechService.stop()
        playbackState = .idle
        currentParagraphIndex = nil
        progress = 0
    }

    func playFromParagraph(_ index: Int) {
        speechService.stop()
        startPlaying(from: index)
    }

    func seek(to targetProgress: Double) {
        let clamped = min(max(targetProgress, 0), 1)
        let targetChar = Int(clamped * Double(totalChars))

        var targetIndex = 0
        for i in 0..<paragraphs.count {
            if i + 1 < charOffsets.count && charOffsets[i + 1] <= targetChar {
                targetIndex = i + 1
            } else {
                break
            }
        }
        targetIndex = min(targetIndex, paragraphs.count - 1)

        speechService.stop()
        startPlaying(from: targetIndex)
    }

    private func startPlaying(from index: Int) {
        guard index < paragraphs.count else {
            playbackState = .idle
            currentParagraphIndex = nil
            progress = 0
            return
        }

        generation &+= 1
        let expectedGeneration = generation

        currentParagraphIndex = index
        playbackState = .playing
        updateProgress(paragraphProgress: 0)

        speechService.speak(paragraphs[index].content, rate: rate, onProgress: { [weak self] charProgress in
            Task { @MainActor in
                guard let self, self.generation == expectedGeneration else { return }
                self.updateProgress(paragraphProgress: charProgress)
            }
        }, onFinish: { [weak self] in
            Task { @MainActor in
                guard let self, self.generation == expectedGeneration else { return }
                self.advanceToNext()
            }
        })
    }

    private func updateProgress(paragraphProgress: Double) {
        guard let index = currentParagraphIndex, index < charOffsets.count else { return }
        let base = Double(charOffsets[index])
        let paragraphLen = Double(paragraphs[index].content.count)
        progress = (base + paragraphLen * paragraphProgress) / Double(totalChars)
    }

    private func advanceToNext() {
        guard let current = currentParagraphIndex else { return }
        let next = current + 1
        if next < paragraphs.count {
            startPlaying(from: next)
        } else {
            playbackState = .idle
            currentParagraphIndex = nil
            progress = 0
        }
    }
}
