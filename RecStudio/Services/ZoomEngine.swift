import Foundation
import CoreGraphics

struct ZoomKeyframe {
    let time: TimeInterval
    let rect: CGRect
}

final class ZoomEngine {
    private let sourceSize: CGSize
    private let maxZoom: CGFloat
    private let smoothingFactor: CGFloat = 0.95

    init(sourceSize: CGSize, maxZoom: CGFloat = 2.0) {
        self.sourceSize = sourceSize
        self.maxZoom = maxZoom
    }

    func computeKeyframes(from cursorPoints: [CursorPoint]) -> [ZoomKeyframe] {
        guard cursorPoints.count > 1 else {
            return [ZoomKeyframe(time: 0, rect: CGRect(origin: .zero, size: sourceSize))]
        }

        let velocities = computeVelocities(cursorPoints)
        let smoothedVelocities = exponentialSmooth(velocities, factor: 0.9)

        let maxV = smoothedVelocities.max() ?? 1
        let threshold = maxV * 0.25

        var zoomLevels: [CGFloat] = smoothedVelocities.map { v in
            if v < threshold {
                let t = 1 - (v / threshold)
                return 1.0 + (maxZoom - 1.0) * t * t
            }
            return 1.0
        }

        zoomLevels = exponentialSmooth(zoomLevels, factor: smoothingFactor)

        var smoothX = cursorPoints[0].x
        var smoothY = cursorPoints[0].y
        var keyframes: [ZoomKeyframe] = []

        for (i, point) in cursorPoints.enumerated() {
            smoothX = smoothX * 0.92 + point.x * 0.08
            smoothY = smoothY * 0.92 + point.y * 0.08

            let zoom = zoomLevels[i]
            let visibleW = sourceSize.width / zoom
            let visibleH = sourceSize.height / zoom

            var x = smoothX - visibleW / 2
            var y = smoothY - visibleH / 2

            x = max(0, min(x, sourceSize.width - visibleW))
            y = max(0, min(y, sourceSize.height - visibleH))

            keyframes.append(ZoomKeyframe(
                time: point.timestamp,
                rect: CGRect(x: x, y: y, width: visibleW, height: visibleH)
            ))
        }

        return keyframes
    }

    func interpolatedRect(at time: TimeInterval, keyframes: [ZoomKeyframe]) -> CGRect {
        guard !keyframes.isEmpty else { return CGRect(origin: .zero, size: sourceSize) }
        guard keyframes.count > 1 else { return keyframes[0].rect }

        if time <= keyframes.first!.time { return keyframes.first!.rect }
        if time >= keyframes.last!.time { return keyframes.last!.rect }

        var lo = 0
        var hi = keyframes.count - 1
        while lo < hi - 1 {
            let mid = (lo + hi) / 2
            if keyframes[mid].time <= time {
                lo = mid
            } else {
                hi = mid
            }
        }

        let lower = keyframes[lo]
        let upper = keyframes[hi]
        let dt = upper.time - lower.time
        guard dt > 0 else { return lower.rect }

        let t = CGFloat((time - lower.time) / dt)
        let s = t * t * (3 - 2 * t)

        return CGRect(
            x: lower.rect.origin.x + (upper.rect.origin.x - lower.rect.origin.x) * s,
            y: lower.rect.origin.y + (upper.rect.origin.y - lower.rect.origin.y) * s,
            width: lower.rect.width + (upper.rect.width - lower.rect.width) * s,
            height: lower.rect.height + (upper.rect.height - lower.rect.height) * s
        )
    }

    // MARK: - Private Helpers

    private func computeVelocities(_ points: [CursorPoint]) -> [CGFloat] {
        var velocities: [CGFloat] = [0]
        for i in 1..<points.count {
            let dt = points[i].timestamp - points[i - 1].timestamp
            guard dt > 0 else {
                velocities.append(velocities.last ?? 0)
                continue
            }
            let dx = points[i].x - points[i - 1].x
            let dy = points[i].y - points[i - 1].y
            velocities.append(sqrt(dx * dx + dy * dy) / CGFloat(dt))
        }
        return velocities
    }

    private func exponentialSmooth(_ values: [CGFloat], factor: CGFloat) -> [CGFloat] {
        guard var prev = values.first else { return [] }
        var result: [CGFloat] = [prev]
        for i in 1..<values.count {
            prev = prev * factor + values[i] * (1 - factor)
            result.append(prev)
        }
        return result
    }
}
