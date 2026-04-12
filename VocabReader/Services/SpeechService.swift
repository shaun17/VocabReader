import AVFoundation

protocol SpeechServiceProtocol {
    func speak(_ text: String, rate: Float, onProgress: @escaping (Double) -> Void, onFinish: @escaping () -> Void)
    func pause()
    func resume()
    func stop()
    var isSpeaking: Bool { get }
    var isPaused: Bool { get }
}

final class SpeechService: NSObject, SpeechServiceProtocol {
    private let synthesizer = AVSpeechSynthesizer()
    private var onFinish: (() -> Void)?
    private var onProgress: ((Double) -> Void)?
    private var utteranceLength: Int = 0
    private var activeUtterance: AVSpeechUtterance?

    override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
    }

    var isSpeaking: Bool { synthesizer.isSpeaking }
    var isPaused: Bool { synthesizer.isPaused }

    func speak(_ text: String, rate: Float, onProgress: @escaping (Double) -> Void, onFinish: @escaping () -> Void) {
        self.onProgress = onProgress
        self.onFinish = onFinish
        self.utteranceLength = text.count
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.preferredVoice()
        utterance.rate = rate
        utterance.pitchMultiplier = 1.0
        utterance.preUtteranceDelay = 0.1
        utterance.postUtteranceDelay = 0.2
        activeUtterance = utterance
        synthesizer.speak(utterance)
    }

    func pause() {
        synthesizer.pauseSpeaking(at: .word)
    }

    func resume() {
        synthesizer.continueSpeaking()
    }

    func stop() {
        activeUtterance = nil
        onFinish = nil
        onProgress = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func configureAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private static func preferredVoice() -> AVSpeechSynthesisVoice? {
        let enVoices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
        return enVoices.first ?? AVSpeechSynthesisVoice(language: "en-US")
    }
}

extension SpeechService: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        guard utterance === activeUtterance, utteranceLength > 0 else { return }
        let progress = Double(characterRange.location + characterRange.length) / Double(utteranceLength)
        onProgress?(progress)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard utterance === activeUtterance else { return }
        activeUtterance = nil
        let finish = onFinish
        onFinish = nil
        onProgress = nil
        finish?()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        // Don't clear callbacks here — stop() already cleared them.
        // If didCancel fires for a stale utterance after a new speak(), this is a no-op.
        guard utterance === activeUtterance else { return }
        activeUtterance = nil
        onFinish = nil
        onProgress = nil
    }
}
