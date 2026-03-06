import AVFoundation
import Combine
import UIKit

// MARK: - VideoProcessor

@MainActor
final class VideoProcessor: ObservableObject {

    @Published var progress: Double = 0.0
    @Published var isProcessing = false

    private var exportSession: AVAssetExportSession?

    // MARK: - Public API

    func process(
        segment1URL: URL,
        segment2URL: URL,
        settings: ExportSettings,
        completion: @escaping (Result<(URL, Int64), any Error>) -> Void
    ) {
        isProcessing = true
        progress = 0

        Task {
            do {
                let result = try await buildAndExport(
                    segment1URL: segment1URL,
                    segment2URL: segment2URL,
                    settings: settings
                )
                self.isProcessing = false
                completion(.success(result))
            } catch {
                self.isProcessing = false
                completion(.failure(error))
            }
        }
    }

    func cancel() {
        exportSession?.cancelExport()
        isProcessing = false
    }

    // MARK: - Core Processing

    private func buildAndExport(
        segment1URL: URL,
        segment2URL: URL,
        settings: ExportSettings
    ) async throws -> (URL, Int64) {

        let asset1 = AVURLAsset(url: segment1URL)
        let asset2 = AVURLAsset(url: segment2URL)

        let duration1 = try await asset1.load(.duration)
        let duration2 = try await asset2.load(.duration)
        let totalDuration = CMTimeAdd(duration1, duration2)

        let vTracks1 = try await asset1.loadTracks(withMediaType: .video)
        let vTracks2 = try await asset2.loadTracks(withMediaType: .video)
        let aTracks1 = try await asset1.loadTracks(withMediaType: .audio)
        let aTracks2 = try await asset2.loadTracks(withMediaType: .audio)

        guard let vTrack1 = vTracks1.first, let vTrack2 = vTracks2.first else {
            throw ProcessorError.noVideoTrack
        }

        // Build composition
        let composition = AVMutableComposition()
        guard
            let compVideo = composition.addMutableTrack(withMediaType: .video,  preferredTrackID: kCMPersistentTrackID_Invalid),
            let compAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw ProcessorError.compositionFailed }

        // Insert video segments
        try compVideo.insertTimeRange(CMTimeRange(start: .zero, duration: duration1), of: vTrack1, at: .zero)
        try compVideo.insertTimeRange(CMTimeRange(start: .zero, duration: duration2), of: vTrack2, at: duration1)

        // Insert audio segments
        if let aTrack1 = aTracks1.first {
            try compAudio.insertTimeRange(CMTimeRange(start: .zero, duration: duration1), of: aTrack1, at: .zero)
        }
        if let aTrack2 = aTracks2.first {
            try compAudio.insertTimeRange(CMTimeRange(start: .zero, duration: duration2), of: aTrack2, at: duration1)
        }

        // Load track properties for transform
        let naturalSize1        = try await vTrack1.load(.naturalSize)
        let preferredTransform1 = try await vTrack1.load(.preferredTransform)
        let naturalSize2        = try await vTrack2.load(.naturalSize)
        let preferredTransform2 = try await vTrack2.load(.preferredTransform)

        let targetSize = settings.resolution.size

        // Build video composition
        let videoComposition = AVMutableVideoComposition()
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(settings.frameRate))
        videoComposition.renderSize = targetSize

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: totalDuration)

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideo)
        let t1 = scaleTransform(naturalSize: naturalSize1, preferredTransform: preferredTransform1, target: targetSize)
        layerInstruction.setTransform(t1, at: .zero)
        let t2 = scaleTransform(naturalSize: naturalSize2, preferredTransform: preferredTransform2, target: targetSize)
        layerInstruction.setTransform(t2, at: duration1)

        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        // Watermark overlay
        if settings.includeWatermark {
            applyWatermark(to: videoComposition, targetSize: targetSize, settings: settings)
        }

        // Pick preset based on user-selected codec + resolution.
        // Note: precise bitrate control requires AVAssetWriter; presets encode quality tiers.
        let preset = exportPreset(codec: settings.codec, resolution: settings.resolution)
        let outputURL = makeOutputURL(format: settings.outputFormat)
        guard let exporter = AVAssetExportSession(asset: composition, presetName: preset)
        else { throw ProcessorError.exportFailed }

        exporter.videoComposition = videoComposition
        exportSession = exporter

        // Track progress concurrently while export runs
        let progressTask = Task { @MainActor [weak self, weak exporter] in
            guard let exporter else { return }
            for await state in exporter.states(updateInterval: 0.1) {
                if case .exporting(let p) = state {
                    self?.progress = p.fractionCompleted
                }
            }
        }

        // Export (throws on failure)
        try await exporter.export(to: outputURL, as: settings.outputFormat.avFileType)
        progressTask.cancel()
        progress = 1.0

        let attrs = try? FileManager.default.attributesOfItem(atPath: outputURL.path)
        let fileSize = attrs?[.size] as? Int64 ?? 0
        return (outputURL, fileSize)
    }

    // MARK: - Export Preset

    private func exportPreset(codec: VideoCodec, resolution: Resolution) -> String {
        switch codec {
        case .hevc:
            switch resolution {
            case .hd720:   return AVAssetExportPresetHEVC1920x1080  // no dedicated 720p HEVC preset
            case .fhd1080: return AVAssetExportPresetHEVC1920x1080
            case .uhd4k:   return AVAssetExportPresetHEVC3840x2160
            }
        case .h264:
            switch resolution {
            case .hd720:   return AVAssetExportPreset1280x720
            case .fhd1080: return AVAssetExportPreset1920x1080
            case .uhd4k:   return AVAssetExportPreset3840x2160
            }
        }
    }

    // MARK: - Scale Transform

    private func scaleTransform(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        target: CGSize
    ) -> CGAffineTransform {
        // Effective display size after rotation
        let rendered = naturalSize.applying(preferredTransform)
        let display  = CGSize(width: abs(rendered.width), height: abs(rendered.height))

        let scale = max(target.width / display.width, target.height / display.height)

        var t = preferredTransform
        t.a  *= scale; t.b  *= scale
        t.c  *= scale; t.d  *= scale
        t.tx  = t.tx * scale + (target.width  - display.width  * scale) / 2
        t.ty  = t.ty * scale + (target.height - display.height * scale) / 2
        return t
    }

    // MARK: - Watermark

    private func applyWatermark(to videoComposition: AVMutableVideoComposition,
                                targetSize: CGSize,
                                settings: ExportSettings) {
        let parentLayer = CALayer()
        let videoLayer  = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: targetSize)
        videoLayer.frame  = CGRect(origin: .zero, size: targetSize)
        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(buildWatermarkLayer(frameSize: targetSize, settings: settings))

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )
    }

    private func buildWatermarkLayer(frameSize: CGSize, settings: ExportSettings) -> CALayer {
        let size: CGFloat = frameSize.height * 0.12
        let gap:  CGFloat = size * 0.15
        let pad:  CGFloat = size * 0.12

        let showIcon = settings.includeIconWatermark
        let showQR   = settings.includeQROverlay
        let itemCount = (showIcon ? 1 : 0) + (showQR ? 1 : 0)

        let containerW = pad + CGFloat(itemCount) * size + CGFloat(max(0, itemCount - 1)) * gap + pad
        let containerH = pad + size + pad

        let container = CALayer()
        container.frame = CGRect(
            x: frameSize.width - containerW - 20,
            y: 20,
            width: containerW,
            height: containerH
        )
        container.backgroundColor = UIColor.black.withAlphaComponent(0.63).cgColor
        container.cornerRadius    = size * 0.12

        var xOffset: CGFloat = pad

        if showIcon {
            let iconLayer = CALayer()
            if let icon = UIImage(named: "AppIcon")?.cgImage {
                iconLayer.contents = icon
            } else {
                iconLayer.backgroundColor = UIColor.systemBlue.cgColor
            }
            iconLayer.frame         = CGRect(x: xOffset, y: pad, width: size, height: size)
            iconLayer.cornerRadius  = size * 0.1
            iconLayer.masksToBounds = true
            container.addSublayer(iconLayer)
            xOffset += size + gap
        }

        if showQR {
            let qrLayer = CALayer()
            if let qr = UIImage(named: "qr")?.cgImage {
                qrLayer.contents = qr
            } else {
                qrLayer.backgroundColor = UIColor.white.cgColor
            }
            qrLayer.frame = CGRect(x: xOffset, y: pad, width: size, height: size)
            container.addSublayer(qrLayer)
        }

        return container
    }

    // MARK: - Helpers

    private func makeOutputURL(format: OutputFormat = .mp4) -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let name = "output_\(Int(Date().timeIntervalSince1970)).\(format.fileExtension)"
        let url = dir.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
        return url
    }

    // MARK: - Errors

    enum ProcessorError: Error, LocalizedError {
        case noVideoTrack, compositionFailed, exportFailed

        var errorDescription: String? {
            switch self {
            case .noVideoTrack:      return "No video track found in segment."
            case .compositionFailed: return "Failed to build video composition."
            case .exportFailed:      return "Video export failed."
            }
        }
    }
}
