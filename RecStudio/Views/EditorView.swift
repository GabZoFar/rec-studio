import SwiftUI
import AVKit

struct EditorView: View {
    @EnvironmentObject var appState: AppState
    @State private var player: AVPlayer?
    @State private var isExporting = false
    @State private var showSavePanel = false

    var body: some View {
        HStack(spacing: 0) {
            // Video preview
            videoPreview
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().background(Color.appBorder)

            // Settings sidebar
            settingsSidebar
                .frame(width: 280)
        }
        .onAppear { setupPlayer() }
    }

    // MARK: - Video Preview

    private var videoPreview: some View {
        VStack(spacing: 16) {
            if let player {
                VideoPlayer(player: player)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.3), radius: 20)
                    .padding(24)
            }

            // Playback controls
            HStack(spacing: 16) {
                Button(action: { player?.seek(to: .zero); player?.play() }) {
                    Image(systemName: "play.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.appTextPrimary)

                Button(action: { player?.pause() }) {
                    Image(systemName: "pause.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.appTextPrimary)

                Spacer()

                Button(action: newRecording) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("New Recording")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.appTextSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Settings Sidebar

    private var settingsSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                sidebarHeader
                zoomSettings
                styleSettings
                exportSection
            }
            .padding(20)
        }
        .background(Color.appSurface.opacity(0.5))
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Export Settings")
                .font(.headline)
                .foregroundStyle(Color.appTextPrimary)
            Text("Customize your video before exporting")
                .font(.caption)
                .foregroundStyle(Color.appTextSecondary)
        }
    }

    // MARK: - Zoom Settings

    private var zoomSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingSectionTitle("Zoom", icon: "magnifyingglass")

            Toggle("Auto Zoom", isOn: $appState.exportSettings.enableZoom)
                .toggleStyle(.switch)
                .tint(.appAccent)

            if appState.exportSettings.enableZoom {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Max Zoom")
                        Spacer()
                        Text(String(format: "%.1fx", appState.exportSettings.maxZoom))
                            .foregroundStyle(Color.appAccent)
                    }
                    .font(.subheadline)
                    Slider(value: $appState.exportSettings.maxZoom, in: 1.2...4.0, step: 0.1)
                        .tint(.appAccent)
                }
            }
        }
        .settingCard()
    }

    // MARK: - Style Settings

    private var styleSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingSectionTitle("Style", icon: "paintbrush")

            // Background presets
            VStack(alignment: .leading, spacing: 6) {
                Text("Background")
                    .font(.subheadline)
                    .foregroundStyle(Color.appTextSecondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 36))], spacing: 8) {
                    ForEach(BackgroundPreset.allCases) { preset in
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [preset.colors.start, preset.colors.end],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 32, height: 32)
                            .overlay {
                                if appState.exportSettings.background == preset {
                                    Circle()
                                        .strokeBorder(.white, lineWidth: 2)
                                }
                            }
                            .onTapGesture {
                                appState.exportSettings.background = preset
                            }
                    }
                }
            }

            // Corner radius
            settingSlider(
                title: "Corner Radius",
                value: $appState.exportSettings.cornerRadius,
                range: 0...32,
                format: "%.0f px"
            )

            // Padding
            settingSlider(
                title: "Padding",
                value: $appState.exportSettings.padding,
                range: 0...120,
                format: "%.0f px"
            )

            // Shadow
            settingSlider(
                title: "Shadow",
                value: $appState.exportSettings.shadowRadius,
                range: 0...60,
                format: "%.0f"
            )
        }
        .settingCard()
    }

    // MARK: - Export Section

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingSectionTitle("Export", icon: "square.and.arrow.up")

            // Resolution picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Resolution")
                    .font(.subheadline)
                    .foregroundStyle(Color.appTextSecondary)
                Picker("", selection: $appState.exportSettings.width) {
                    Text("1080p").tag(1920)
                    Text("1440p").tag(2560)
                    Text("4K").tag(3840)
                }
                .pickerStyle(.segmented)
            }

            if isExporting {
                VStack(spacing: 8) {
                    ProgressView(value: appState.exportProgress)
                        .tint(.appAccent)
                    Text("\(Int(appState.exportProgress * 100))%")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.appTextSecondary)
                }
                .padding(.top, 4)
            } else {
                Button(action: exportVideo) {
                    HStack(spacing: 8) {
                        Image(systemName: "film")
                        Text("Export Video")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.appAccent)
                    )
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .settingCard()
    }

    // MARK: - Helpers

    private func settingSectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.appTextPrimary)
    }

    private func settingSlider(
        title: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        format: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .foregroundStyle(Color.appAccent)
            }
            .font(.subheadline)
            Slider(value: value, in: range)
                .tint(.appAccent)
        }
    }

    private func setupPlayer() {
        guard let url = appState.rawVideoURL else { return }
        player = AVPlayer(url: url)
    }

    private func newRecording() {
        player?.pause()
        player = nil
        appState.rawVideoURL = nil
        appState.exportedVideoURL = nil
        appState.exportProgress = 0
        appState.screenRecorder.cursorTracker.reset()
        withAnimation { appState.phase = .setup }
    }

    private func exportVideo() {
        guard let sourceURL = appState.rawVideoURL else { return }

        updateResolutionHeight()

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "RecStudio Export.mp4"

        guard panel.runModal() == .OK, let outputURL = panel.url else { return }

        isExporting = true
        appState.exportProgress = 0

        Task {
            do {
                let exporter = VideoExporter()
                try await exporter.export(
                    sourceURL: sourceURL,
                    outputURL: outputURL,
                    cursorEvents: appState.screenRecorder.cursorTracker.events,
                    settings: appState.exportSettings
                ) { progress in
                    DispatchQueue.main.async {
                        appState.exportProgress = progress
                    }
                }

                await MainActor.run {
                    isExporting = false
                    appState.exportedVideoURL = outputURL
                    NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    appState.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func updateResolutionHeight() {
        switch appState.exportSettings.width {
        case 2560: appState.exportSettings.height = 1440
        case 3840: appState.exportSettings.height = 2160
        default:   appState.exportSettings.height = 1080
        }
    }
}

// MARK: - Setting Card Modifier

extension View {
    func settingCard() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.appSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.appBorder, lineWidth: 1)
                    )
            )
    }
}
