import SwiftUI

struct ArticlePlayerBar: View {
    @ObservedObject var player: ArticleAudioPlayerViewModel
    @State private var isDragging = false
    @State private var dragValue: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.readingRule)
                .frame(height: 0.5)

            HStack(spacing: 12) {
                Slider(
                    value: isDragging ? $dragValue : $player.progress,
                    in: 0...1
                ) { editing in
                    if editing {
                        isDragging = true
                        dragValue = player.progress
                    } else {
                        player.seek(to: dragValue)
                        isDragging = false
                    }
                }
                .tint(Color.readingTitle)

                playerButton(icon: playButtonIcon) {
                    player.togglePlayback()
                }

                if player.playbackState != .idle {
                    playerButton(icon: "stop.fill") {
                        player.stop()
                    }
                }

                Menu {
                    Picker("语速", selection: Binding(
                        get: { player.rate },
                        set: { player.setRate($0) }
                    )) {
                        Text("0.5×").tag(Float(0.35))
                        Text("1.0×").tag(Float(0.5))
                        Text("1.5×").tag(Float(0.55))
                        Text("2.0×").tag(Float(0.6))
                    }
                } label: {
                    Text(rateLabel)
                        .font(.system(.caption, design: .serif).weight(.medium))
                        .foregroundStyle(Color.readingTitle)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(Color.readingTitle.opacity(0.3), lineWidth: 1)
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color.readingBackground.ignoresSafeArea(.container, edges: .bottom))
    }

    private func playerButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.readingTitle)
                .frame(width: 28, height: 28)
        }
    }

    private var playButtonIcon: String {
        player.playbackState == .playing ? "pause.fill" : "play.fill"
    }

    private var rateLabel: String {
        switch player.rate {
        case 0.35: return "0.5×"
        case 0.5: return "1.0×"
        case 0.55: return "1.5×"
        case 0.6: return "2.0×"
        default: return "1.0×"
        }
    }
}
