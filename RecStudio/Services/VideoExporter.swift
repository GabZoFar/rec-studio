import Foundation
import AVFoundation
import CoreImage
import CoreGraphics

enum ExportError: LocalizedError {
    case noVideoTrack
    case bufferCreationFailed
    case writerFailed(String)
    case readerFailed(String)

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: return "No video track found in the source file."
        case .bufferCreationFailed: return "Failed to create pixel buffer."
        case .writerFailed(let msg): return "Writer error: \(msg)"
        case .readerFailed(let msg): return "Reader error: \(msg)"
        }
    }
}

final class VideoExporter {
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    func export(
        sourceURL: URL,
        outputURL: URL,
        cursorEvents: [CursorEvent],
        settings: ExportSettings,
        progress: @escaping (Double) -> Void
    ) async throws {
        let asset = AVAsset(url: sourceURL)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw ExportError.noVideoTrack
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let duration = try await asset.load(.duration)

        let zoomEngine = ZoomEngine(sourceSize: naturalSize, maxZoom: settings.maxZoom)
        let keyframes = settings.enableZoom
            ? zoomEngine.computeKeyframes(from: cursorEvents)
            : [ZoomKeyframe(time: 0, rect: CGRect(origin: .zero, size: naturalSize))]

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        reader.add(readerOutput)

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let writerInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: settings.width,
                AVVideoHeightKey: settings.height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: settings.bitRate,
                    AVVideoMaxKeyFrameIntervalKey: settings.frameRate,
                ] as [String: Any],
            ]
        )
        writerInput.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: settings.width,
                kCVPixelBufferHeightKey as String: settings.height,
            ]
        )

        writer.add(writerInput)
        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let outputSize = CGSize(width: settings.width, height: settings.height)
        let totalSeconds = duration.seconds
        let bgImage = createGradientBackground(
            size: outputSize,
            startColor: settings.background.cgColors.start,
            endColor: settings.background.cgColors.end
        )
        let mask = createRoundedRectMask(
            size: contentSize(outputSize: outputSize, padding: settings.padding),
            cornerRadius: settings.cornerRadius
        )

        while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }

            let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let seconds = time.seconds

            let zoomRect = settings.enableZoom
                ? zoomEngine.interpolatedRect(at: seconds, keyframes: keyframes)
                : CGRect(origin: .zero, size: naturalSize)

            let processedBuffer = try compositeFrame(
                pixelBuffer: pixelBuffer,
                zoomRect: zoomRect,
                outputSize: outputSize,
                background: bgImage,
                mask: mask,
                settings: settings
            )

            while !writerInput.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.005)
            }

            adaptor.append(processedBuffer, withPresentationTime: time)

            if totalSeconds > 0 {
                progress(min(seconds / totalSeconds, 1.0))
            }
        }

        writerInput.markAsFinished()
        await writer.finishWriting()

        if writer.status == .failed {
            throw ExportError.writerFailed(writer.error?.localizedDescription ?? "Unknown")
        }

        reader.cancelReading()
        progress(1.0)
    }

    // MARK: - Compositing

    private func contentSize(outputSize: CGSize, padding: CGFloat) -> CGSize {
        CGSize(
            width: outputSize.width - padding * 2,
            height: outputSize.height - padding * 2
        )
    }

    private func compositeFrame(
        pixelBuffer: CVPixelBuffer,
        zoomRect: CGRect,
        outputSize: CGSize,
        background: CIImage,
        mask: CIImage,
        settings: ExportSettings
    ) throws -> CVPixelBuffer {
        let contentArea = contentSize(outputSize: outputSize, padding: settings.padding)

        var frame = CIImage(cvPixelBuffer: pixelBuffer)

        frame = frame.cropped(to: zoomRect)
        frame = frame.transformed(by: CGAffineTransform(
            translationX: -zoomRect.origin.x, y: -zoomRect.origin.y
        ))

        let scaleX = contentArea.width / zoomRect.width
        let scaleY = contentArea.height / zoomRect.height
        frame = frame.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        let maskedFrame = frame.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(),
            kCIInputMaskImageKey: mask,
        ])

        let shadow = maskedFrame
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.4),
            ])
            .applyingFilter("CIGaussianBlur", parameters: [
                kCIInputRadiusKey: settings.shadowRadius,
            ])
            .cropped(to: CGRect(
                x: -settings.shadowRadius * 2,
                y: -settings.shadowRadius * 2,
                width: contentArea.width + settings.shadowRadius * 4,
                height: contentArea.height + settings.shadowRadius * 4
            ))
            .transformed(by: CGAffineTransform(translationX: 0, y: -4))

        let translate = CGAffineTransform(translationX: settings.padding, y: settings.padding)
        let positionedShadow = shadow.transformed(by: translate)
        let positionedFrame = maskedFrame.transformed(by: translate)

        let composite = positionedFrame
            .composited(over: positionedShadow)
            .composited(over: background)
            .cropped(to: CGRect(origin: .zero, size: outputSize))

        var outputBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(outputSize.width),
            Int(outputSize.height),
            kCVPixelFormatType_32BGRA,
            nil,
            &outputBuffer
        )
        guard status == kCVReturnSuccess, let buffer = outputBuffer else {
            throw ExportError.bufferCreationFailed
        }

        ciContext.render(composite, to: buffer)
        return buffer
    }

    // MARK: - Asset Generation

    private func createGradientBackground(
        size: CGSize, startColor: CGColor, endColor: CGColor
    ) -> CIImage {
        let w = Int(size.width)
        let h = Int(size.height)
        guard let ctx = CGContext(
            data: nil,
            width: w, height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
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

    private func createRoundedRectMask(size: CGSize, cornerRadius: CGFloat) -> CIImage {
        let w = Int(size.width)
        let h = Int(size.height)
        guard let ctx = CGContext(
            data: nil,
            width: w, height: h,
            bitsPerComponent: 8,
            bytesPerRow: w,
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
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
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
