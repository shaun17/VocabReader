import SwiftUI

@main
struct VocabReaderApp: App {
    @StateObject private var settings = SettingsStore.shared

    var body: some Scene {
        WindowGroup {
            if settings.isConfigured {
                TodayView()
            } else {
                SettingsView(settings: settings, onSave: nil)
            }
        }
    }

}
