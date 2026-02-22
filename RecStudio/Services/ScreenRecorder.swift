import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreImage
import AppKit

final class ScreenRecorder: NSObject, ObservableObject {
    @Published var availableDisplays: [SCDisplay] = []
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var previewImage: CGImage?
    @Published var permissionDenied = false

    private(set) var recordedVideoURL: URL?
    private(set) var cursorTracker = CursorTracker()

    private var stream: SCStream?
    private var streamOutput: StreamCaptureOutput?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var firstFrameTime: CMTime?
    private var durationTimer: Timer?
    private var recordingStartDate: Date?

    // Preview compositing state — set at recording start, read on main thread
    private var currentSettings = ExportSettings()
    private var zoomEngine: ZoomEngine?
    private var previewBackground: CIImage?
    private var previewMask: CIImage?
    private var previewOutputSize: CGSize = .zero
    /// Scaled video dimensions within the content area (preserves source aspect ratio).
    private var previewContentSize: CGSize = .zero
    /// Offset to center the video inside the padded content area (pillarbox / letterbox).
    private var previewVideoOffset: CGPoint = .zero
    private var previewPadding: CGFloat = 0

    private let captureQueue = DispatchQueue(label: "com.recstudio.capture", qos: .userInitiated)
    // Shared CIContext — never create one per frame.
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    @MainActor
    func refreshAvailableContent() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
            availableDisplays = content.displays
            permissionDenied = false
        } catch {
            permissionDenied = true
        }
    }

    @MainActor
    func startRecording(
        display: SCDisplay,
        captureMode: CaptureMode = .fullScreen,
        frameRate: Int = 60,
        settings: ExportSettings = ExportSettings()
    ) async throws {
        // Clear stale preview from any previous session immediately.
        previewImage = nil
        currentSettings = settings

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let appBundleID = Bundle.main.bundleIdentifier ?? ""
        let excludedWindows = content.windows.filter {
            $0.owningApplication?.bundleIdentifier == appBundleID
        }

        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)

        // Use the selected display's own backing scale, not NSScreen.main's.
        let scaleFactor = NSScreen.screens.first(where: {
            guard let n = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDirectDisplayID(n.uint32Value) == display.displayID
        })?.backingScaleFactor ?? 2.0

        let config = SCStreamConfiguration()
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true

        // captureRect is in the global CGEvent/Quartz coordinate space so that
        // cursor positions (also Quartz) subtract correctly.
        let displayBounds = CGDisplayBounds(display.displayID)
        let captureRect: CGRect

        switch captureMode {
        case .fullScreen:
            config.width = Int(CGFloat(display.width) * scaleFactor)
            config.height = Int(CGFloat(display.height) * scaleFactor)
            // Use the display's actual global origin so cursor offsets are correct
            // on non-primary displays.
            captureRect = CGRect(
                x: displayBounds.origin.x,
                y: displayBounds.origin.y,
                width: CGFloat(display.width),
                height: CGFloat(display.height)
            )

        case .region(let rect):
            config.sourceRect = rect
            config.width = Int(rect.width * scaleFactor)
            config.height = Int(rect.height * scaleFactor)
            captureRect = CGRect(
                x: displayBounds.origin.x + rect.origin.x,
                y: displayBounds.origin.y + rect.origin.y,
                width: rect.width,
                height: rect.height
            )
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("recstudio_\(UUID().uuidString).mov")

        let writer = try AVAssetWriter(outputURL: tempURL, fileType: .mov)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: config.width,
            AVVideoHeightKey: config.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 25_000_000,
                AVVideoMaxKeyFrameIntervalKey: frameRate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ] as [String: Any],
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true

        let bufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: config.width,
                kCVPixelBufferHeightKey as String: config.height,
            ]
        )

        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        self.assetWriter = writer
        self.videoInput = input
        self.adaptor = bufferAdaptor
        self.firstFrameTime = nil
        self.recordedVideoURL = tempURL

        let captureStream = SCStream(filter: filter, configuration: config, delegate: self)

        let output = StreamCaptureOutput { [weak self] buffer in
            self?.handleCapturedFrame(buffer)
        }
        self.streamOutput = output

        try captureStream.addStreamOutput(output, type: .screen, sampleHandlerQueue: captureQueue)
        try await captureStream.startCapture()

        self.stream = captureStream

        cursorTracker.startTracking(
            captureRect: captureRect,
            scaleFactor: scaleFactor
        )

        // Build preview compositing assets now that we know source size.
        let sourceSize = CGSize(width: config.width, height: config.height)
        setupPreviewAssets(sourceSize: sourceSize, settings: settings)

        recordingStartDate = Date()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let start = self?.recordingStartDate else { return }
            DispatchQueue.main.async {
                self?.recordingDuration = Date().timeIntervalSince(start)
            }
        }

        isRecording = true
    }

    @MainActor
    func stopRecording() async throws {
        durationTimer?.invalidate()
        durationTimer = nil
        cursorTracker.stopTracking()

        try await stream?.stopCapture()
        stream = nil
        streamOutput = nil

        videoInput?.markAsFinished()
        await assetWriter?.finishWriting()

        isRecording = false
    }

    // MARK: - Preview Asset Setup

    /// Pre-builds the background CIImage and rounded-rect mask used in every preview frame.
    /// Called once per recording session on the main thread.
    private func setupPreviewAssets(sourceSize: CGSize, settings: ExportSettings) {
        // Scale the export output size down to a manageable preview resolution
        // while keeping the same aspect ratio.
        let exportW = CGFloat(settings.width)
        let exportH = CGFloat(settings.height)
        let scale = min(800 / exportW, 450 / exportH)
        let pvW = exportW * scale
        let pvH = exportH * scale
        previewOutputSize = CGSize(width: pvW, height: pvH)

        let pvScale = pvW / exportW
        previewPadding = settings.padding * pvScale
        let contentW = pvW - previewPadding * 2
        let contentH = pvH - previewPadding * 2

        // Fit the source video inside the content area while preserving its aspect ratio.
        // previewContentSize is the actual video size (not the full content area), so the
        // scaleX/scaleY formulas in updatePreview become uniform automatically.
        let fitToContent = min(contentW / sourceSize.width, contentH / sourceSize.height)
        let scaledVideoW = sourceSize.width  * fitToContent
        let scaledVideoH = sourceSize.height * fitToContent
        previewContentSize = CGSize(width: scaledVideoW, height: scaledVideoH)
        previewVideoOffset = CGPoint(
            x: (contentW - scaledVideoW) / 2,
            y: (contentH - scaledVideoH) / 2
        )

        let scaledRadius = settings.cornerRadius * pvScale

        previewBackground = makeGradientBackground(
            size: previewOutputSize,
            startColor: settings.background.cgColors.start,
            endColor: settings.background.cgColors.end
        )
        previewMask = makeRoundedRectMask(
            size: previewContentSize,
            cornerRadius: scaledRadius
        )

        zoomEngine = ZoomEngine(sourceSize: sourceSize, maxZoom: settings.maxZoom)
    }

    // MARK: - Frame Handling

    private func handleCapturedFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let input = videoInput,
              input.isReadyForMoreMediaData
        else { return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if firstFrameTime == nil {
            firstFrameTime = timestamp
        }

        let relativeTime = CMTimeSubtract(timestamp, firstFrameTime!)
        adaptor?.append(pixelBuffer, withPresentationTime: relativeTime)

        let frameIdx = Int(relativeTime.seconds * 60)
        if frameIdx % 6 == 0 {
            let t = relativeTime.seconds
            // Dispatch to main thread so we can safely read cursorTracker.events
            // (which is written on the main thread by the timer and click monitor).
            DispatchQueue.main.async { [weak self] in
                self?.updatePreview(from: pixelBuffer, at: t)
            }
        }
    }

    // Runs on main thread — safe to read cursorTracker.events.
    private func updatePreview(from pixelBuffer: CVPixelBuffer, at time: TimeInterval) {
        var frame = CIImage(cvPixelBuffer: pixelBuffer)

        // Apply zoom if enabled
        if currentSettings.enableZoom, let engine = zoomEngine {
            let events = cursorTracker.events
            let keyframes = engine.computeKeyframes(from: events)
            let zoomRect = engine.interpolatedRect(at: time, keyframes: keyframes)

            if zoomRect.width > 0, zoomRect.height > 0 {
                frame = frame
                    .cropped(to: zoomRect)
                    .transformed(by: CGAffineTransform(
                        translationX: -zoomRect.origin.x, y: -zoomRect.origin.y
                    ))

                let scaleX = previewContentSize.width / zoomRect.width
                let scaleY = previewContentSize.height / zoomRect.height
                frame = frame.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            } else {
                frame = scaleFrameToContent(frame)
            }
        } else {
            frame = scaleFrameToContent(frame)
        }

        // Apply rounded-rect mask
        if let mask = previewMask {
            frame = frame.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: CIImage.empty(),
                kCIInputMaskImageKey: mask,
            ])
        }

        // Position over background (padding + letterbox/pillarbox offset)
        let translate = CGAffineTransform(
            translationX: previewPadding + previewVideoOffset.x,
            y: previewPadding + previewVideoOffset.y
        )
        let positionedFrame = frame.transformed(by: translate)

        let composite: CIImage
        if let bg = previewBackground {
            composite = positionedFrame
                .composited(over: bg)
                .cropped(to: CGRect(origin: .zero, size: previewOutputSize))
        } else {
            composite = positionedFrame
                .cropped(to: CGRect(origin: .zero, size: previewOutputSize))
        }

        guard let cgImage = ciContext.createCGImage(composite, from: composite.extent) else { return }
        previewImage = cgImage
    }

    private func scaleFrameToContent(_ frame: CIImage) -> CIImage {
        let src = frame.extent
        guard src.width > 0, src.height > 0 else { return frame }
        let scaleX = previewContentSize.width / src.width
        let scaleY = previewContentSize.height / src.height
        return frame.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
    }

    // MARK: - Display

    func displayThumbnail(for display: SCDisplay) -> CGImage? {
        CGDisplayCreateImage(display.displayID)
    }

    // MARK: - CIImage Asset Builders

    private func makeGradientBackground(
        size: CGSize, startColor: CGColor, endColor: CGColor
    ) -> CIImage {
        let w = Int(size.width), h = Int(size.height)
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: size))
        }
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [startColor, endColor] as CFArray,
            locations: [0, 1]
        ) else {
            return CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: size))
        }
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: CGFloat(h)),
            end: CGPoint(x: CGFloat(w), y: 0),
            options: []
        )
        guard let cgImage = ctx.makeImage() else {
            return CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: size))
        }
        return CIImage(cgImage: cgImage)
    }

    private func makeRoundedRectMask(size: CGSize, cornerRadius: CGFloat) -> CIImage {
        let w = Int(size.width), h = Int(size.height)
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return CIImage(color: .white).cropped(to: CGRect(origin: .zero, size: size))
        }
        ctx.setFillColor(.black)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(.white)
        let path = CGPath(
            roundedRect: CGRect(origin: .zero, size: size),
            cornerWidth: cornerRadius, cornerHeight: cornerRadius,
            transform: nil
        )
        ctx.addPath(path)
        ctx.fillPath()
        guard let cgImage = ctx.makeImage() else {
            return CIImage(color: .white).cropped(to: CGRect(origin: .zero, size: size))
        }
        return CIImage(cgImage: cgImage)
    }
}

// MARK: - SCStreamDelegate

extension ScreenRecorder: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        DispatchQueue.main.async { [weak self] in
            self?.isRecording = false
        }
    }
}

// MARK: - Stream Output Handler

private final class StreamCaptureOutput: NSObject, SCStreamOutput {
    let handler: (CMSampleBuffer) -> Void

    init(handler: @escaping (CMSampleBuffer) -> Void) {
        self.handler = handler
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen else { return }
        handler(sampleBuffer)
    }
}
