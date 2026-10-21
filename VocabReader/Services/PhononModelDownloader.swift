import CryptoKit
import Foundation
import os
import PhononTTS

/// 按 bundle.json 逐个下载 Phonon 模型文件，替代 SDK 的 `PhononModels.download`。
///
/// SDK 用 async `download(from:delegate:)`，系统不会回调写入进度，进度条只能按文件跳，
/// 三个大文件占了总量的九成；大文件中途断开也只能从头重下。这里改用带 delegate 的下载任务按字节报告进度，
/// 失败时用 resume data 从断点续传。目录布局与校验方式与 SDK 一致：先下到 staging，
/// 每个文件校验大小和 SHA-256，全部就位后再替换，`Phonon.load` 与 `PhononModels.isInstalled` 照常可用。
final class PhononModelDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private struct Manifest: Decodable {
        struct File: Decodable {
            let path: String
            let size: Int
            let sha256: String
        }

        let built: Int
        let files: [File]
    }

    /// 当前下载任务的跨线程状态；delegate 回调在 URLSession 的队列上。
    private struct TaskState {
        var task: URLSessionDownloadTask?
        var continuation: CheckedContinuation<URL, Error>?
        var bytesBefore: Int64 = 0
        var fileSize: Int64 = 0
        var reportedBytes: Int64 = 0
    }

    private static let logger = Logger(subsystem: "com.vocabreader.app", category: "PhononModelDownloader")
    /// 进度至少前进这么多字节才回调一次，避免每个网络包都刷新界面。
    private static let reportStep: Int64 = 512 * 1024

    private let base: URL
    private let destination: URL
    private let maxAttempts: Int
    private let onProgress: @Sendable (Double) -> Void
    private let state = OSAllocatedUnfairLock(initialState: TaskState())
    private var totalBytes: Int64 = 1
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)

    init(
        base: URL,
        destination: URL = PhononModels.defaultDirectory,
        maxAttempts: Int = 3,
        onProgress: @escaping @Sendable (Double) -> Void
    ) {
        self.base = base
        self.destination = destination
        self.maxAttempts = maxAttempts
        self.onProgress = onProgress
    }

    /// 下载并安装模型，返回可交给 `Phonon.load` 的目录；同一版本已安装时直接返回。
    func run() async throws -> URL {
        // session 持有 delegate，结束时必须失效，否则下载器不会释放。
        defer { session.finishTasksAndInvalidate() }

        let fm = FileManager.default
        let (data, response) = try await session.data(from: base.appending(path: "bundle.json"))
        try Self.check(response, "bundle.json")
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        if PhononModels.isInstalled(at: destination), installedBuild() == manifest.built {
            onProgress(1)
            return destination
        }

        // 与 SDK 相同的 staging 命名，放在目标旁边，最后一步是同卷重命名。
        let staging = destination.deletingLastPathComponent()
            .appending(path: "\(destination.lastPathComponent).partial-\(manifest.built)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)

        totalBytes = max(manifest.files.reduce(0) { $0 + Int64($1.size) }, 1)
        var done: Int64 = 0
        for file in manifest.files {
            let target = staging.appending(path: file.path)
            if try !Self.matches(target, file) {
                let downloaded = try await download(file, bytesBefore: done)
                guard try Self.matches(downloaded, file) else {
                    try? fm.removeItem(at: downloaded)
                    throw PhononError(description: "\(file.path) 的大小或 SHA-256 不匹配")
                }
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fm.removeItem(at: target)
                try fm.moveItem(at: downloaded, to: target)
            }
            done += Int64(file.size)
            report(bytes: done, force: true)
        }

        try data.write(to: staging.appending(path: "bundle.json"))
        try? fm.removeItem(at: destination)
        try fm.moveItem(at: staging, to: destination)
        var installed = destination
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try installed.setResourceValues(values)
        return destination
    }

    /// 单个文件的下载与重试；网络错误时带上 resume data 续传，不重下已到手的部分。
    private func download(_ file: Manifest.File, bytesBefore: Int64) async throws -> URL {
        let url = base.appending(path: file.path)
        var resumeData: Data?
        var attempt = 1
        while true {
            do {
                return try await startTask(url: url, resumeData: resumeData, bytesBefore: bytesBefore, size: Int64(file.size))
            } catch let error as URLError where attempt < maxAttempts && error.code != .cancelled {
                resumeData = error.downloadTaskResumeData
                Self.logger.info("Download \(file.path, privacy: .public) attempt \(attempt, privacy: .public) failed (\(error.code.rawValue, privacy: .public)), resume data \(resumeData != nil, privacy: .public)")
                attempt += 1
                try await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func startTask(url: URL, resumeData: Data?, bytesBefore: Int64, size: Int64) async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = resumeData.map { session.downloadTask(withResumeData: $0) } ?? session.downloadTask(with: url)
                state.withLock { state in
                    state.task = task
                    state.continuation = continuation
                    state.bytesBefore = bytesBefore
                    state.fileSize = size
                }
                task.resume()
            }
        } onCancel: {
            state.withLock { $0.task }?.cancel()
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        let continuation = state.withLock { state -> CheckedContinuation<URL, Error>? in
            defer {
                state.continuation = nil
                state.task = nil
            }
            return state.continuation
        }
        continuation?.resume(with: result)
    }

    /// 只在前进足够多或文件完成时回调，并保证进度单调不减。
    private func report(bytes: Int64, force: Bool = false) {
        let shouldReport = state.withLock { state -> Bool in
            guard bytes > state.reportedBytes, force || bytes - state.reportedBytes >= Self.reportStep else { return false }
            state.reportedBytes = bytes
            return true
        }
        if shouldReport {
            onProgress(min(Double(bytes) / Double(totalBytes), 1))
        }
    }

    private func installedBuild() -> Int? {
        (try? Data(contentsOf: destination.appending(path: "bundle.json")))
            .flatMap { try? JSONDecoder().decode(Manifest.self, from: $0) }?
            .built
    }

    private static func check(_ response: URLResponse?, _ what: String) throws {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw PhononError(description: "\(what)：HTTP \(http.statusCode)")
        }
    }

    private static func matches(_ url: URL, _ file: Manifest.File) throws -> Bool {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size == file.size else { return false }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 8 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined() == file.sha256
    }

    // MARK: URLSessionDownloadDelegate

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let (before, size) = state.withLock { ($0.bytesBefore, $0.fileSize) }
        report(bytes: before + min(totalBytesWritten, size))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            try Self.check(downloadTask.response, downloadTask.originalRequest?.url?.lastPathComponent ?? "file")
            // 系统在回调返回后就删除临时文件，必须当场移走。
            let kept = FileManager.default.temporaryDirectory.appending(path: "phonon-\(UUID().uuidString)")
            try FileManager.default.moveItem(at: location, to: kept)
            finish(.success(kept))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // 成功时 didFinishDownloadingTo 已经交付结果，这里只处理失败。
        if let error {
            finish(.failure(error))
        }
    }
}
