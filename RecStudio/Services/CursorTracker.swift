import Foundation
import CoreGraphics

struct CursorPoint: Codable {
    let timestamp: TimeInterval
    let x: CGFloat
    let y: CGFloat
}

final class CursorTracker {
    private(set) var points: [CursorPoint] = []
    private var timer: Timer?
    private var startTime: Date?
    private var displayOrigin: CGPoint = .zero
    private var scaleFactor: CGFloat = 2

    func startTracking(displayBounds: CGRect, scaleFactor: CGFloat) {
        self.displayOrigin = displayBounds.origin
        self.scaleFactor = scaleFactor
        self.points = []
        self.startTime = Date()

        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.recordPosition()
        }
        RunLoop.main.add(t, forMode: .common)
        self.timer = t
    }

    func stopTracking() {
        timer?.invalidate()
        timer = nil
    }

    func reset() {
        stopTracking()
        points = []
    }

    private func recordPosition() {
        guard let startTime else { return }
        guard let event = CGEvent(source: nil) else { return }

        let location = event.location
        let elapsed = Date().timeIntervalSince(startTime)

        let point = CursorPoint(
            timestamp: elapsed,
            x: (location.x - displayOrigin.x) * scaleFactor,
            y: (location.y - displayOrigin.y) * scaleFactor
        )
        points.append(point)
    }
}
