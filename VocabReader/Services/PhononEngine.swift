import Foundation
import os
import PhononTTS

/// 管理 Phonon 模型的获取与加载；模型加载一次后常驻，避免每次朗读重复编译。
///
/// 模型来源按优先级：App 内置目录（仅 Debug 包含，方便真机调试）→ 已下载到本机的模型 →
/// 用户在设置页主动触发的网络下载。启动时只加载已有模型，绝不自动下载。
final class PhononEngine: ObservableObject, @unchecked Sendable {
    enum Status: Equatable {
        case idle
        case notDownloaded
        case downloading(Double)
        case preparing(String)
        case ready
        case failed(String)
    }

    static let shared = PhononEngine()

    static let bundledModelsName = "PhononModels"
    /// 设置页试听用的示例句。
    static let previewText = "Reading a little every day helps new words stick."
    /// 模型包解压后的总大小，下载按单个文件进行，不经过压缩。
    static let downloadSizeDescription = "163 MB"

    private static let logger = Logger(subsystem: "com.vocabreader.app", category: "PhononEngine")

    /// 模拟器没有神经引擎，只能退回 CPU 推理。
    private static var computeUnit: ComputeUnit {
        #if targetEnvironment(simulator)
        return .cpu
        #else
        return .neuralEngine
        #endif
    }

    /// 模型下载地址来自构建配置；为空表示当前包无法获取模型，设置页不提供 Phonon。
    static let remoteBaseURL: URL? = {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: "PhononModelsBaseURL") as? String,
            !value.isEmpty
        else { return nil }
        return URL(string: value)
    }()

    @MainActor @Published private(set) var status: Status = .idle
    @MainActor private var prepareTask: Task<Void, Never>?
    /// 正在试听的音色，用于设置页显示播放状态。
    @MainActor @Published private(set) var previewingVoice: String?
    @MainActor private var previewService: PhononSpeechService?
    private let loaded = OSAllocatedUnfairLock<Phonon?>(initialState: nil)
    private let voice = OSAllocatedUnfairLock(initialState: PhononVoice.defaultName)
    private let previewVoice = OSAllocatedUnfairLock(initialState: PhononVoice.defaultName)

    /// 已加载的模型；朗读服务在任意线程读取。
    var phonon: Phonon? {
        loaded.withLock { $0 }
    }

    /// 文章朗读使用的音色，来自设置。
    var selectedVoice: String {
        voice.withLock { $0 }
    }

    /// 记录设置里的音色；模型已加载时提前切换，省掉下一段开头的切换耗时。
    @MainActor
    func selectVoice(_ name: String) async {
        voice.withLock { $0 = name }
        guard let phonon, phonon.voice != name, phonon.voices.contains(name) else { return }
        do {
            try await phonon.setVoice(name)
        } catch {
            Self.logger.error("Phonon setVoice failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// 用指定音色朗读示例句；再次点击同一音色停止。
    @MainActor
    func togglePreview(_ name: String) {
        if previewingVoice == name {
            stopPreview()
            return
        }
        guard let phonon else { return }
        if previewService == nil {
            previewService = try? PhononSpeechService(phonon: phonon) { [weak self] in
                self?.previewVoice.withLock { $0 } ?? PhononVoice.defaultName
            }
        }
        guard let previewService else { return }

        previewVoice.withLock { $0 = name }
        previewingVoice = name
        previewService.speak(Self.previewText, rate: 0.5, onProgress: { _ in }, onFinish: { [weak self] in
            self?.previewingVoice = nil
        })
    }

    @MainActor
    func stopPreview() {
        previewService?.stop()
        previewingVoice = nil
    }

    /// 当前包是否有办法拿到模型。
    var isAvailable: Bool {
        Self.bundledModelsURL != nil || Self.remoteBaseURL != nil || PhononModels.isInstalled()
    }

    private static var bundledModelsURL: URL? {
        Bundle.main.url(forResource: bundledModelsName, withExtension: nil)
    }

    /// 加载已有模型；`allowDownload` 为 true 时，本机没有模型会先下载。重复调用会等待同一次任务。
    @MainActor
    func prepare(allowDownload: Bool = false) async {
        if phonon != nil { return }
        if let prepareTask { return await prepareTask.value }

        let task = Task { await load(allowDownload: allowDownload) }
        prepareTask = task
        await task.value
        prepareTask = nil
    }

    @MainActor
    private func load(allowDownload: Bool) async {
        do {
            let clock = ContinuousClock()
            let start = clock.now

            guard let directory = try await obtainModels(allowDownload: allowDownload) else {
                status = .notDownloaded
                return
            }
            let obtained = clock.now

            let needsCompiling = Phonon.needsCompiling(directory)
            status = .preparing(needsCompiling ? "首次使用，正在为本机编译模型…" : "正在加载模型…")
            let tts = try await Phonon.load(models: directory, language: .english, computeUnit: Self.computeUnit)
            if tts.voices.contains(selectedVoice) {
                try await tts.setVoice(selectedVoice)
            }
            let ready = clock.now

            loaded.withLock { $0 = tts }
            status = .ready
            Self.logger.info("Phonon ready: obtain \(String(describing: obtained - start), privacy: .public), load \(String(describing: ready - obtained), privacy: .public), compiled \(needsCompiling, privacy: .public), voice \(tts.voice, privacy: .public)")
        } catch {
            Self.logger.error("Phonon load failed: \(String(describing: error), privacy: .public)")
            status = .failed(Self.message(for: error))
        }
    }

    /// 返回可加载的模型目录；没有模型且不允许下载时返回 nil。
    @MainActor
    private func obtainModels(allowDownload: Bool) async throws -> URL? {
        if let source = Self.bundledModelsURL {
            status = .preparing("正在安装模型…")
            return try await Task.detached(priority: .userInitiated) {
                try PhononModels.install(bundled: source)
            }.value
        }

        if PhononModels.isInstalled() {
            return PhononModels.defaultDirectory
        }

        guard allowDownload, let base = Self.remoteBaseURL else { return nil }
        status = .downloading(0)

        let downloader = PhononModelDownloader(base: base) { [weak self] fraction in
            Task { @MainActor in
                guard let self, case .downloading = self.status else { return }
                self.status = .downloading(fraction)
            }
        }
        return try await downloader.run()
    }

    private static func message(for error: Error) -> String {
        if let urlError = error as? URLError {
            return "网络错误（\(urlError.code.rawValue)），请检查网络后重试"
        }
        return String(describing: error)
    }
}
