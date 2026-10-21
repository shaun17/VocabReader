import AVFoundation
import os
import PhononTTS

/// 用 Phonon 流式合成并播放单段文本。
///
/// Phonon 不提供单词时间戳，进度按“已播采样 / 预计总采样”估算，生成结束后改用实际总长；
/// 语速通过变速不变调实现，因为 Swift 接口没有暴露语速参数。
/// 合成回调在后台线程，凡是跨线程的状态都放在 `state` 锁里，并用 generation 丢弃旧段落的音频。
final class PhononSpeechService: SpeechServiceProtocol, @unchecked Sendable {
    private struct State {
        var generation: UInt = 0
        var generatedSamples = 0
        var isGenerationComplete = false
    }

    /// 按英文常速约每秒 13 个字符估算一段话的采样数，只在生成结束前使用。
    private static let estimatedSamplesPerCharacter = Phonon.sampleRate / 13
    /// 段落末尾补一段静音，与系统语音的 postUtteranceDelay 保持相近的停顿。
    private static let trailingSilence = 0.2

    private static let logger = Logger(subsystem: "com.vocabreader.app", category: "PhononSpeechService")

    private let phonon: Phonon
    /// 每段开始时读取应使用的音色，文章朗读和设置页试听各自提供。
    private let voice: @Sendable () -> String
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private let format: AVAudioFormat
    private let state = OSAllocatedUnfairLock(initialState: State())

    private var synthesisTask: Task<Void, Never>?
    private var progressTimer: Timer?
    private var onProgress: ((Double) -> Void)?
    private var onFinish: (() -> Void)?
    private var estimatedSamples: Double = 1

    private(set) var isSpeaking = false
    private(set) var isPaused = false

    init(phonon: Phonon, voice: @escaping @Sendable () -> String) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Phonon.sampleRate, channels: 1) else {
            throw PhononError(description: "无法创建 Phonon 音频格式")
        }
        self.phonon = phonon
        self.voice = voice
        self.format = format
        engine.attach(player)
        engine.attach(timePitch)
        engine.connect(player, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
        try engine.start()
    }

    deinit {
        synthesisTask?.cancel()
        progressTimer?.invalidate()
        player.stop()
        engine.stop()
    }

    /// 把播放条上的四档语速映射为播放倍速，与界面标签一致。
    static func playbackRate(for speechRate: Float) -> Float {
        switch speechRate {
        case ..<0.45: return 0.5
        case ..<0.525: return 1.0
        case ..<0.575: return 1.5
        default: return 2.0
        }
    }

    func speak(_ text: String, rate: Float, onProgress: @escaping (Double) -> Void, onFinish: @escaping () -> Void) {
        stop()
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                Self.logger.error("Audio engine failed to start: \(String(describing: error))")
            }
        }

        let expected = state.withLock { state -> UInt in
            state.generatedSamples = 0
            state.isGenerationComplete = false
            return state.generation
        }
        self.onProgress = onProgress
        self.onFinish = onFinish
        estimatedSamples = max(Double(text.count) * Self.estimatedSamplesPerCharacter, 1)
        timePitch.rate = Self.playbackRate(for: rate)
        isSpeaking = true
        isPaused = false
        player.play()
        startProgressTimer()

        let phonon = phonon
        let voiceName = self.voice()
        synthesisTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                // 模型同一时间只有一个当前音色，试听和文章朗读共用模型，所以每段开始前对齐一次。
                if phonon.voice != voiceName, phonon.voices.contains(voiceName) {
                    try await phonon.setVoice(voiceName)
                }
                try await phonon.speak(text) { samples in
                    self?.enqueue(samples, generation: expected)
                }
            } catch {
                Self.logger.error("Phonon synthesis failed: \(String(describing: error))")
            }
            guard !Task.isCancelled else { return }
            self?.finishScheduling(generation: expected)
        }
    }

    func pause() {
        guard isSpeaking, !isPaused else { return }
        player.pause()
        isPaused = true
    }

    func resume() {
        guard isSpeaking, isPaused else { return }
        player.play()
        isPaused = false
    }

    func stop() {
        state.withLock { $0.generation &+= 1 }
        synthesisTask?.cancel()
        synthesisTask = nil
        stopProgressTimer()
        onProgress = nil
        onFinish = nil
        isSpeaking = false
        isPaused = false
        player.stop()
    }

    /// 在锁内调度，保证 stop() 递增 generation 之后不会再有旧段落的音频排进播放队列。
    private func enqueue(_ samples: [Float], generation: UInt) {
        guard let buffer = makeBuffer(samples) else { return }
        state.withLock { state in
            guard state.generation == generation else { return }
            state.generatedSamples += samples.count
            player.scheduleBuffer(buffer)
        }
    }

    /// 生成结束后排入尾部静音，以它播完作为整段结束的信号。
    private func finishScheduling(generation: UInt) {
        let silence = [Float](repeating: 0, count: Int(Phonon.sampleRate * Self.trailingSilence))
        guard let buffer = makeBuffer(silence) else { return }
        state.withLock { state in
            guard state.generation == generation else { return }
            state.isGenerationComplete = true
            player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.handlePlaybackFinished(generation: generation)
                }
            }
        }
    }

    private func handlePlaybackFinished(generation: UInt) {
        guard isSpeaking, state.withLock({ $0.generation == generation }) else { return }
        isSpeaking = false
        stopProgressTimer()
        onProgress?(1)
        let finish = onFinish
        onProgress = nil
        onFinish = nil
        finish?()
    }

    private func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard
            !samples.isEmpty,
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
            let channel = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        return buffer
    }

    private func startProgressTimer() {
        stopProgressTimer()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.reportProgress()
        }
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func reportProgress() {
        guard
            isSpeaking,
            !isPaused,
            let nodeTime = player.lastRenderTime,
            let playerTime = player.playerTime(forNodeTime: nodeTime)
        else { return }

        let played = Double(max(playerTime.sampleTime, 0))
        let (generated, isComplete) = state.withLock { ($0.generatedSamples, $0.isGenerationComplete) }
        let total = isComplete ? Double(max(generated, 1)) : max(Double(generated), estimatedSamples)
        onProgress?(min(played / total, 1))
    }
}
