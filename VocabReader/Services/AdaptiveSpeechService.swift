import Foundation

/// 每段开始朗读时按设置选择 Phonon 或系统语音；Phonon 未就绪或音频引擎创建失败时回退到系统语音。
final class AdaptiveSpeechService: SpeechServiceProtocol {
    private let system: SpeechServiceProtocol
    private let prefersPhonon: () -> Bool
    private let engine: PhononEngine
    private var phononService: PhononSpeechService?
    private var active: SpeechServiceProtocol

    init(
        system: SpeechServiceProtocol = SpeechService(),
        prefersPhonon: @escaping () -> Bool = { SettingsStore.shared.speechEngine == .phonon },
        engine: PhononEngine = .shared
    ) {
        self.system = system
        self.prefersPhonon = prefersPhonon
        self.engine = engine
        self.active = system
    }

    var isSpeaking: Bool { active.isSpeaking }
    var isPaused: Bool { active.isPaused }

    func speak(_ text: String, rate: Float, onProgress: @escaping (Double) -> Void, onFinish: @escaping () -> Void) {
        let next = resolveService()
        if (next is PhononSpeechService) != (active is PhononSpeechService) {
            active.stop()
        }
        active = next
        active.speak(text, rate: rate, onProgress: onProgress, onFinish: onFinish)
    }

    func pause() {
        active.pause()
    }

    func resume() {
        active.resume()
    }

    func stop() {
        active.stop()
    }

    private func resolveService() -> SpeechServiceProtocol {
        guard prefersPhonon(), let phonon = engine.phonon else { return system }
        if let phononService { return phononService }
        phononService = try? PhononSpeechService(phonon: phonon) { [engine] in engine.selectedVoice }
        return phononService ?? system
    }
}
