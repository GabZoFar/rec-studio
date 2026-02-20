import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            switch appState.phase {
            case .setup:
                SetupView()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))

            case .countdown(let count):
                CountdownView(count: count)
                    .transition(.opacity)

            case .recording:
                RecordingView()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))

            case .processing:
                ProcessingView()
                    .transition(.opacity)

            case .editing:
                EditorView()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appState.phase)
    }
}

// MARK: - Countdown Overlay

struct CountdownView: View {
    let count: Int

    var body: some View {
        VStack {
            Text("\(count)")
                .font(.system(size: 120, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .appAccent.opacity(0.5), radius: 30)
                .contentTransition(.numericText())

            Text("Recording starts in...")
                .font(.title3)
                .foregroundStyle(Color.appTextSecondary)
        }
    }
}

// MARK: - Processing View

struct ProcessingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.appAccent)

            Text("Processing recording...")
                .font(.title3.weight(.medium))
                .foregroundStyle(Color.appTextPrimary)
        }
    }
}
