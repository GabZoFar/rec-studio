import SwiftUI
import ScreenCaptureKit

struct SetupView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.appBorder)
            ScrollView {
                VStack(spacing: 28) {
                    displayPicker
                    captureModeSection
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
            if appState.screenRecorder.permissionDenied {
                permissionPrompt
            } else if displays.isEmpty {
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

    private var permissionPrompt: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.shield")
                .font(.system(size: 36))
                .foregroundStyle(Color.appAccent)

            Text("Screen Recording Permission Required")
                .font(.headline)
                .foregroundStyle(Color.appTextPrimary)

            Text("RecStudio needs permission to capture your screen. Open System Settings and enable RecStudio under Privacy & Security → Screen Recording.")
                .font(.subheadline)
                .foregroundStyle(Color.appTextSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            HStack(spacing: 12) {
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.appAccent)

                Button("Retry") {
                    Task { await appState.screenRecorder.refreshAvailableContent() }
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Capture Mode

    private var captureModeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Capture Mode", systemImage: "crop")
                .font(.headline)
                .foregroundStyle(Color.appTextPrimary)

            HStack(spacing: 12) {
                captureModeButton(
                    title: "Full Screen",
                    icon: "display",
                    isSelected: !appState.captureMode.isRegion
                ) {
                    withAnimation { appState.captureMode = .fullScreen }
                }

                captureModeButton(
                    title: "Select Region",
                    icon: "rectangle.dashed",
                    isSelected: appState.captureMode.isRegion
                ) {
                    showRegionPicker()
                }
            }

            if let rect = appState.captureMode.regionRect {
                HStack(spacing: 10) {
                    Image(systemName: "viewfinder")
                        .foregroundStyle(Color.appAccent)
                    Text("\(Int(rect.width)) × \(Int(rect.height))")
                        .font(.system(.subheadline, design: .monospaced).weight(.medium))
                        .foregroundStyle(Color.appTextPrimary)
                    Text("at (\(Int(rect.origin.x)), \(Int(rect.origin.y)))")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                    Spacer()
                    Button("Change") { showRegionPicker() }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.appAccent)
                        .buttonStyle(.plain)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.appAccent.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.appAccent.opacity(0.3), lineWidth: 1)
                        )
                )
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

    private func captureModeButton(
        title: String, icon: String, isSelected: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline)
                Text(title)
                    .font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.appAccent.opacity(0.2) : Color.appSurfaceHover)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                isSelected ? Color.appAccent : Color.appBorder,
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    )
            )
            .foregroundStyle(isSelected ? Color.appAccent : Color.appTextSecondary)
        }
        .buttonStyle(.plain)
    }

    private func showRegionPicker() {
        let picker = RegionPickerController()
        let state = appState

        picker.onRegionSelected = { rect in
            DispatchQueue.main.async {
                state.captureMode = .region(rect)
                state.regionPickerController = nil
            }
        }
        picker.onCancelled = {
            DispatchQueue.main.async {
                state.regionPickerController = nil
            }
        }

        appState.regionPickerController = picker
        picker.show()
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
        Button(action: startRecording) {
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
        .disabled(!canRecord)
        .opacity(canRecord ? 1 : 0.5)
    }

    private var canRecord: Bool {
        if appState.captureMode.isRegion { return appState.captureMode.regionRect != nil }
        return appState.selectedDisplay != nil
    }

    private func startRecording() {
        Task { await appState.beginRecording() }
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
