import AVFoundation
import Combine
import Foundation

// MARK: - Data Models

struct RecordedSegments {
    let video1URL: URL
    let video2URL: URL
}

enum OutputFormat: String, CaseIterable, Identifiable {
    case mp4 = "MP4"
    case mov = "MOV"
    var id: String { rawValue }
    var avFileType: AVFoundation.AVFileType { self == .mp4 ? .mp4 : .mov }
    var fileExtension: String { self == .mp4 ? "mp4" : "mov" }
}

struct ExportSettings {
    var resolution: Resolution     = .fhd1080
    var codec: VideoCodec          = .h264
    var frameRate: Int             = 30
    var outputFormat: OutputFormat = .mp4
    var includeQROverlay: Bool     = true
    var includeIconWatermark: Bool = true
    var includeWatermark: Bool { includeQROverlay || includeIconWatermark }
}

enum Resolution: String, CaseIterable, Identifiable {
    case hd720   = "720p"
    case fhd1080 = "1080p"
    case uhd4k   = "4K"

    var id: String { rawValue }

    var size: CGSize {
        switch self {
        case .hd720:   return CGSize(width: 720,  height: 1280)
        case .fhd1080: return CGSize(width: 1080, height: 1920)
        case .uhd4k:   return CGSize(width: 2160, height: 3840)
        }
    }

    var bitrate: Int {
        switch self {
        case .hd720:   return 4_000_000
        case .fhd1080: return 8_000_000
        case .uhd4k:   return 25_000_000
        }
    }
}

enum VideoCodec: String, CaseIterable, Identifiable {
    case h264 = "H.264"
    case hevc = "HEVC"

    var id: String { rawValue }

    var avCodecType: AVVideoCodecType {
        switch self {
        case .h264: return .h264
        case .hevc: return .hevc
        }
    }
}

// MARK: - Navigation

enum Route {
    case camera, exportSettings, processing, exportComplete
}

// MARK: - App State

@MainActor
final class FlowState: ObservableObject {
    @Published var route: Route = .camera
    @Published var segments: RecordedSegments?
    @Published var settings: ExportSettings = ExportSettings()
    @Published var outputURL: URL?
    @Published var fileSizeBytes: Int64 = 0
}
