import Foundation
import CoreGraphics

struct ZoomKeyframe {
    let time: TimeInterval
    let rect: CGRect
}

final class ZoomEngine {
    private let sourceSize: CGSize
    private let maxZoom: CGFloat

    private let zoomInDuration: TimeInterval = 0.3
    private let holdAfterLastClick: TimeInterval = 1.2
    private let zoomOutDuration: TimeInterval = 0.5
    private let clusterGap: TimeInterval = 2.0

    init(sourceSize: CGSize, maxZoom: CGFloat = 2.0) {
        self.sourceSize = sourceSize
        self.maxZoom = maxZoom
    }

    // MARK: - Public API

    func computeKeyframes(from events: [CursorEvent]) -> [ZoomKeyframe] {
        let moves = events.filter { $0.type == .move }
        guard moves.count > 1 else {
            return [ZoomKeyframe(time: 0, rect: fullRect)]
        }

        let clicks = events.filter { $0.type == .leftClick || $0.type == .rightClick }
        let clusters = buildClusters(from: clicks)

        var smoothCX = moves[0].x
        var smoothCY = moves[0].y
        var keyframes: [ZoomKeyframe] = []

        for move in moves {
            let t = move.timestamp
            let zoom = zoomLevel(at: t, clusters: clusters)

            if zoom > 1.01 {
                let target = zoomTarget(at: t, clusters: clusters) ?? CGPoint(x: move.x, y: move.y)
                smoothCX = smoothCX * 0.85 + target.x * 0.15
                smoothCY = smoothCY * 0.85 + target.y * 0.15
            } else {
                smoothCX = smoothCX * 0.95 + move.x * 0.05
                smoothCY = smoothCY * 0.95 + move.y * 0.05
            }

            let visibleW = sourceSize.width / zoom
            let visibleH = sourceSize.height / zoom
            var x = smoothCX - visibleW / 2
            var y = smoothCY - visibleH / 2
            x = max(0, min(x, sourceSize.width - visibleW))
            y = max(0, min(y, sourceSize.height - visibleH))

            keyframes.append(ZoomKeyframe(
                time: t,
                rect: CGRect(x: x, y: y, width: visibleW, height: visibleH)
            ))
        }

        return keyframes
    }

    func interpolatedRect(at time: TimeInterval, keyframes: [ZoomKeyframe]) -> CGRect {
        guard !keyframes.isEmpty else { return fullRect }
        guard keyframes.count > 1 else { return keyframes[0].rect }

        if time <= keyframes.first!.time { return keyframes.first!.rect }
        if time >= keyframes.last!.time { return keyframes.last!.rect }

        var lo = 0, hi = keyframes.count - 1
        while lo < hi - 1 {
            let mid = (lo + hi) / 2
            if keyframes[mid].time <= time { lo = mid } else { hi = mid }
        }

        let a = keyframes[lo], b = keyframes[hi]
        let dt = b.time - a.time
        guard dt > 0 else { return a.rect }

        let t = CGFloat((time - a.time) / dt)
        let s = t * t * (3 - 2 * t)

        return CGRect(
            x: a.rect.origin.x + (b.rect.origin.x - a.rect.origin.x) * s,
            y: a.rect.origin.y + (b.rect.origin.y - a.rect.origin.y) * s,
            width: a.rect.width + (b.rect.width - a.rect.width) * s,
            height: a.rect.height + (b.rect.height - a.rect.height) * s
        )
    }

    // MARK: - Click Clusters

    private struct ClickCluster {
        var clicks: [(x: CGFloat, y: CGFloat, time: TimeInterval)]

        var firstTime: TimeInterval { clicks.first!.time }
        var lastTime: TimeInterval { clicks.last!.time }

        var zoomInStart: TimeInterval { max(0, firstTime - 0.15) }
        var peakStart: TimeInterval { firstTime + zoomInDuration }
        var holdEnd: TimeInterval { lastTime + holdAfterClick }
        var zoomOutEnd: TimeInterval { lastTime + holdAfterClick + zoomOutDur }

        let zoomInDuration: TimeInterval
        let holdAfterClick: TimeInterval
        let zoomOutDur: TimeInterval

        var center: CGPoint {
            let cx = clicks.map(\.x).reduce(0, +) / CGFloat(clicks.count)
            let cy = clicks.map(\.y).reduce(0, +) / CGFloat(clicks.count)
            return CGPoint(x: cx, y: cy)
        }
    }

    private func buildClusters(from clicks: [CursorEvent]) -> [ClickCluster] {
        guard !clicks.isEmpty else { return [] }

        var groups: [[(x: CGFloat, y: CGFloat, time: TimeInterval)]] = []
        var current: [(x: CGFloat, y: CGFloat, time: TimeInterval)] = [
            (clicks[0].x, clicks[0].y, clicks[0].timestamp)
        ]

        for i in 1..<clicks.count {
            let c = clicks[i]
            if c.timestamp - current.last!.time < clusterGap {
                current.append((c.x, c.y, c.timestamp))
            } else {
                groups.append(current)
                current = [(c.x, c.y, c.timestamp)]
            }
        }
        groups.append(current)

        return groups.map {
            ClickCluster(
                clicks: $0,
                zoomInDuration: zoomInDuration,
                holdAfterClick: holdAfterLastClick,
                zoomOutDur: zoomOutDuration
            )
        }
    }

    // MARK: - Zoom Computation

    private func zoomLevel(at time: TimeInterval, clusters: [ClickCluster]) -> CGFloat {
        for cluster in clusters {
            if time < cluster.zoomInStart || time > cluster.zoomOutEnd { continue }

            if time < cluster.peakStart {
                let t = (time - cluster.zoomInStart) / (cluster.peakStart - cluster.zoomInStart)
                return 1.0 + (maxZoom - 1.0) * easeOutCubic(CGFloat(t))
            } else if time <= cluster.holdEnd {
                return maxZoom
            } else {
                let t = (time - cluster.holdEnd) / (cluster.zoomOutEnd - cluster.holdEnd)
                return 1.0 + (maxZoom - 1.0) * (1.0 - easeInCubic(CGFloat(t)))
            }
        }
        return 1.0
    }

    private func zoomTarget(at time: TimeInterval, clusters: [ClickCluster]) -> CGPoint? {
        for cluster in clusters {
            if time >= cluster.zoomInStart && time <= cluster.zoomOutEnd {
                var best = cluster.clicks[0]
                for click in cluster.clicks where click.time <= time {
                    best = click
                }
                return CGPoint(x: best.x, y: best.y)
            }
        }
        return nil
    }

    // MARK: - Easing

    private func easeOutCubic(_ t: CGFloat) -> CGFloat {
        1 - pow(1 - t, 3)
    }

    private func easeInCubic(_ t: CGFloat) -> CGFloat {
        t * t * t
    }

    private var fullRect: CGRect {
        CGRect(origin: .zero, size: sourceSize)
    }
}
