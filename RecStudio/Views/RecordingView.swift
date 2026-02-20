import SwiftUI

struct RecordingView: View {
    @EnvironmentObject var appState: AppState
    @State private var dotOpacity: Double = 1.0

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Live preview
            if let preview = appState.screenRecorder.previewImage {
                Image(decorative: preview, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.3), radius: 20)
                    .padding(.horizontal, 40)
                    .frame(maxHeight: 350)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.appSurface)
                    .aspectRatio(16 / 10, contentMode: .fit)
                    .overlay {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Capturing screen...")
                                .font(.subheadline)
                                .foregroundStyle(Color.appTextSecondary)
                        }
                    }
                    .padding(.horizontal, 40)
                    .frame(maxHeight: 350)
            }

            // Timer and controls
            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(.red)
                        .frame(width: 10, height: 10)
                        .opacity(dotOpacity)

                    Text("REC")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.red)

                    Text(formatDuration(appState.screenRecorder.recordingDuration))
                        .font(.system(.title2, design: .monospaced).weight(.medium))
                        .foregroundStyle(Color.appTextPrimary)
                        .contentTransition(.numericText())
                }

                Button(action: stopRecording) {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.white)
                            .frame(width: 14, height: 14)
                        Text("Stop Recording")
                            .font(.headline)
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.appRed)
                    )
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape)
            }

            Spacer()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                dotOpacity = 0.3
            }
        }
    }

    private func stopRecording() {
        Task {
            withAnimation { appState.phase = .processing }
            do {
                try await appState.screenRecorder.stopRecording()
                appState.rawVideoURL = appState.screenRecorder.recordedVideoURL
                withAnimation { appState.phase = .editing }
            } catch {
                appState.errorMessage = error.localizedDescription
                withAnimation { appState.phase = .setup }
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration - Double(Int(duration))) * 10)
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }
}
