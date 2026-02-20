import SwiftUI
import ScreenCaptureKit

struct SetupView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.appBorder)
            ScrollView {
                VStack(spacing: 32) {
                    displayPicker
                    settingsSection
                    recordButton
                }
                .padding(32)
            }
        }
        .task {
            await appState.screenRecorder.refreshAvailableContent()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "record.circle")
                .font(.title2)
                .foregroundStyle(Color.appAccent)
            Text("RecStudio")
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.appTextPrimary)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color.appSurface.opacity(0.5))
    }

    // MARK: - Display Picker

    private var displayPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Select Display", systemImage: "display")
                .font(.headline)
                .foregroundStyle(Color.appTextPrimary)

            let displays = appState.screenRecorder.availableDisplays
            if displays.isEmpty {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Requesting screen recording permission...")
                        .font(.subheadline)
                        .foregroundStyle(Color.appTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 40)
            } else {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 16),
                ], spacing: 16) {
                    ForEach(displays, id: \.displayID) { display in
                        DisplayCard(
                            display: display,
                            isSelected: appState.selectedDisplay?.displayID == display.displayID,
                            thumbnail: appState.screenRecorder.displayThumbnail(for: display)
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                appState.selectedDisplay = display
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Settings

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Recording Settings", systemImage: "gearshape")
                .font(.headline)
                .foregroundStyle(Color.appTextPrimary)

            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Frame Rate")
                        .font(.subheadline)
                        .foregroundStyle(Color.appTextSecondary)
                    Picker("", selection: $appState.exportSettings.frameRate) {
                        Text("30 fps").tag(30)
                        Text("60 fps").tag(60)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Auto Zoom")
                        .font(.subheadline)
                        .foregroundStyle(Color.appTextSecondary)
                    Toggle("", isOn: $appState.exportSettings.enableZoom)
                        .toggleStyle(.switch)
                        .tint(.appAccent)
                }

                Spacer()
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.appSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.appBorder, lineWidth: 1)
                )
        )
    }

    // MARK: - Record Button

    private var recordButton: some View {
        Button(action: startCountdown) {
            HStack(spacing: 10) {
                Circle()
                    .fill(.red)
                    .frame(width: 12, height: 12)
                Text("Start Recording")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.appAccent)
            )
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(appState.selectedDisplay == nil)
        .opacity(appState.selectedDisplay == nil ? 0.5 : 1)
    }

    private func startCountdown() {
        guard appState.selectedDisplay != nil else { return }

        Task {
            for i in (1...3).reversed() {
                withAnimation { appState.phase = .countdown(i) }
                try? await Task.sleep(for: .seconds(1))
            }
            await startRecording()
        }
    }

    @MainActor
    private func startRecording() async {
        guard let display = appState.selectedDisplay else { return }
        do {
            try await appState.screenRecorder.startRecording(
                display: display,
                frameRate: appState.exportSettings.frameRate
            )
            withAnimation { appState.phase = .recording }
        } catch {
            appState.errorMessage = error.localizedDescription
            withAnimation { appState.phase = .setup }
        }
    }
}

// MARK: - Display Card

struct DisplayCard: View {
    let display: SCDisplay
    let isSelected: Bool
    let thumbnail: CGImage?
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 10) {
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.appSurface)
                        .aspectRatio(16 / 10, contentMode: .fit)
                        .overlay {
                            Image(systemName: "display")
                                .font(.largeTitle)
                                .foregroundStyle(Color.appTextSecondary)
                        }
                }

                Text("\(display.width) × \(display.height)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.appTextSecondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.appAccent.opacity(0.15) : Color.appSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                isSelected ? Color.appAccent : Color.appBorder,
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
