import AVFoundation

/// 只在真正开始朗读时占用音频会话，结束后交还，避免打开文章就打断其他 App 的音乐。
enum AudioSessionManager {
    static func activate() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(true)
    }

    /// 通知其他 App 可以恢复播放（例如被暂停的音乐）。
    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
