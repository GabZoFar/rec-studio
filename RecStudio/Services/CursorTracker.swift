import Foundation
import CoreGraphics
import AppKit

enum CursorEventType: String, Codable {
    case move
    case leftClick
    case rightClick
}

struct CursorEvent: Codable {
    let timestamp: TimeInterval
    let x: CGFloat
    let y: CGFloat
    let type: CursorEventType
}

final class CursorTracker {
    private(set) var events: [CursorEvent] = []
    private var positionTimer: Timer?
    private var globalClickMonitor: Any?
    private var startTime: Date?
    private(set) var captureOrigin: CGPoint = .zero
    private(set) var captureSize: CGSize = .zero
    private var scaleFactor: CGFloat = 2

    func startTracking(captureRect: CGRect, scaleFactor: CGFloat) {
        self.captureOrigin = captureRect.origin
        self.captureSize = captureRect.size
        self.scaleFactor = scaleFactor
        self.events = []
        self.startTime = Date()

        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.recordPosition()
        }
        RunLoop.main.add(t, forMode: .common)
        self.positionTimer = t

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] nsEvent in
            self?.recordClick(nsEvent)
        }
    }

    func stopTracking() {
        positionTimer?.invalidate()
        positionTimer = nil
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
    }

    func reset() {
        stopTracking()
        events = []
    }

    private func recordPosition() {
        guard let startTime else { return }
        guard let cgEvent = CGEvent(source: nil) else { return }

        let location = cgEvent.location
        let elapsed = Date().timeIntervalSince(startTime)

        events.append(CursorEvent(
            timestamp: elapsed,
            x: (location.x - captureOrigin.x) * scaleFactor,
            y: (location.y - captureOrigin.y) * scaleFactor,
            type: .move
        ))
    }

    private func recordClick(_ nsEvent: NSEvent) {
        guard let startTime else { return }
        // Use the event's own CGEvent location — this is the cursor position at the moment
        // the click occurred. CGEvent(source: nil) would sample the *current* position,
        // which is wrong for subsequent clicks after the cursor has moved.
        guard let location = nsEvent.cgEvent?.location else { return }
        let elapsed = Date().timeIntervalSince(startTime)
        let eventType: CursorEventType = nsEvent.type == .leftMouseDown ? .leftClick : .rightClick

        events.append(CursorEvent(
            timestamp: elapsed,
            x: (location.x - captureOrigin.x) * scaleFactor,
            y: (location.y - captureOrigin.y) * scaleFactor,
            type: eventType
        ))
    }
}
