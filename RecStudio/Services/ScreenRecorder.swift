import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreImage

final class ScreenRecorder: NSObject, ObservableObject {
    @Published var availableDisplays: [SCDisplay] = []
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var previewImage: CGImage?

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

    private let captureQueue = DispatchQueue(label: "com.recstudio.capture", qos: .userInitiated)

    @MainActor
    func refreshAvailableContent() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
            availableDisplays = content.displays
        } catch {
            print("Failed to fetch displays: \(error)")
        }
    }

    @MainActor
    func startRecording(display: SCDisplay, frameRate: Int = 60) async throws {
        // Exclude our own app windows from capture
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let appBundleID = Bundle.main.bundleIdentifier ?? ""
        let excludedWindows = content.windows.filter {
            $0.owningApplication?.bundleIdentifier == appBundleID
        }

        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)

        let config = SCStreamConfiguration()
        config.width = display.width * 2
        config.height = display.height * 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true

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
            displayBounds: CGRect(x: 0, y: 0, width: display.width, height: display.height),
            scaleFactor: 2
        )

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
            updatePreview(from: pixelBuffer)
        }
    }

    private func updatePreview(from pixelBuffer: CVPixelBuffer) {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }

        DispatchQueue.main.async { [weak self] in
            self?.previewImage = cgImage
        }
    }

    func displayThumbnail(for display: SCDisplay) -> CGImage? {
        CGDisplayCreateImage(display.displayID)
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
