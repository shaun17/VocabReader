import SwiftUI

@main
struct VocabReaderApp: App {
    @StateObject private var settings = SettingsStore.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if settings.isConfigured {
                    TodayView()
                } else {
                    SettingsView(
                        settings: settings,
                        showsCancelButton: false
                    )
                }
            }
            .background {
                AppAppearanceWindowBridge(appearance: settings.appearance)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .tint(Color.readingTitle)
        }
    }

}
