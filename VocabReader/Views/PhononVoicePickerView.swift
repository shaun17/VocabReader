import SwiftUI

/// Phonon 音色二级页：按口音分组，点整行选中，右侧按钮单独试听，选择写回设置草稿、保存时生效。
/// 只在模型就绪后才能进入，试听按钮的禁用状态只是兜底。
struct PhononVoicePickerView: View {
    @Binding var selection: String
    @ObservedObject var engine: PhononEngine

    var body: some View {
        ZStack {
            LinedPaperBackground()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(PhononAccent.allCases) { accent in
                        SettingsFieldLabel(accent.title)
                            .padding(.horizontal, 4)
                            .padding(.top, accent == PhononAccent.allCases.first ? 0 : 10)

                        voiceCard(for: accent)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("选择音色")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            engine.stopPreview()
        }
    }

    private func voiceCard(for accent: PhononAccent) -> some View {
        let voices = PhononVoice.voices(for: accent)
        return VStack(spacing: 0) {
            ForEach(voices) { voice in
                voiceRow(voice)

                if voice != voices.last {
                    SettingsDivider()
                }
            }
        }
        .padding(.horizontal, 16)
        .settingsCardBackground()
    }

    private func voiceRow(_ voice: PhononVoice) -> some View {
        let isSelected = selection == voice.name

        return HStack(spacing: 4) {
            Button {
                selection = voice.name
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(voice.name) · \(voice.gender.title)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.readingTextPrimary)

                        Text(voice.summary)
                            .font(.caption)
                            .foregroundStyle(Color.readingTextSecondary)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Color.readingTitle)
                        .opacity(isSelected ? 1 : 0)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 10)
                .frame(minHeight: SettingsStepperMetrics.minimumTouchSize)
                .contentShape(Rectangle())
            }
            .buttonStyle(SettingsPressButtonStyle())
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            previewButton(for: voice)
        }
    }

    private func previewButton(for voice: PhononVoice) -> some View {
        let isPreviewing = engine.previewingVoice == voice.name

        return Button {
            engine.togglePreview(voice.name)
        } label: {
            Image(systemName: isPreviewing ? "stop.circle.fill" : "play.circle")
                .font(.title3)
                .foregroundStyle(Color.readingTitle.opacity(engine.status == .ready ? 1 : 0.35))
                .frame(
                    width: SettingsStepperMetrics.minimumTouchSize,
                    height: SettingsStepperMetrics.minimumTouchSize
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(SettingsPressButtonStyle())
        .disabled(engine.status != .ready)
        .accessibilityLabel(isPreviewing ? "停止试听 \(voice.name)" : "试听 \(voice.name)")
    }
}
