import AVFoundation
import Combine
import Foundation

// MARK: - Recording State

enum RecordingState: Equatable {
    case idle
    case recordingSegment1
    case recordingSegment2
    case completed
}

// MARK: - CameraService

@MainActor
final class CameraService: NSObject, ObservableObject {

    @Published var state: RecordingState = .idle
    @Published var displayTime: String = "00:00"
    @Published var progress: Double = 0.0

    let captureSession = AVCaptureSession()

    private(set) var segment1URL: URL?
    private(set) var segment2URL: URL?
    var onCompleted: ((URL, URL) -> Void)?

    private let movieOutput = AVCaptureMovieFileOutput()
    private var cameraPosition: AVCaptureDevice.Position = .back

    private var timer: Timer?
    private var elapsedTime: TimeInterval = 0
    private var segment1Duration: TimeInterval = 0
    private let maxSegmentDuration: TimeInterval = 30

    private var pendingAction: PendingAction = .none

    private enum PendingAction {
        case none, startSegment2, finish
    }

    override init() {
        super.init()
    }

    // MARK: - Session Setup

    func setupSession() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .hd1920x1080

        if let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let videoInput = try? AVCaptureDeviceInput(device: camera),
           captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        }

        if let mic = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: mic),
           captureSession.canAddInput(audioInput) {
            captureSession.addInput(audioInput)
        }

        if captureSession.canAddOutput(movieOutput) {
            captureSession.addOutput(movieOutput)
        }

        captureSession.commitConfiguration()
    }

    func startSession() {
        guard !captureSession.isRunning else { return }
        Task.detached(priority: .userInitiated) { [session = captureSession] in
            session.startRunning()
        }
    }

    func stopSession() {
        guard captureSession.isRunning else { return }
        Task.detached(priority: .userInitiated) { [session = captureSession] in
            session.stopRunning()
        }
    }

    // MARK: - Recording Control

    func handleRecordButton() {
        switch state {
        case .idle:              startSegment1()
        case .recordingSegment1: stopSegment1()
        case .recordingSegment2: stopSegment2()
        case .completed:         break
        }
    }

    private func startSegment1() {
        let url = cacheURL("segment1.mp4")
        segment1URL = url
        movieOutput.startRecording(to: url, recordingDelegate: self)
        state = .recordingSegment1
        startTimer()
    }

    private func stopSegment1() {
        segment1Duration = elapsedTime
        pendingAction = .startSegment2
        movieOutput.stopRecording()
    }

    private func startSegment2() {
        let url = cacheURL("segment2.mp4")
        segment2URL = url
        movieOutput.startRecording(to: url, recordingDelegate: self)
        state = .recordingSegment2
    }

    private func stopSegment2() {
        pendingAction = .finish
        movieOutput.stopRecording()
        stopTimer()
    }

    // MARK: - Camera Flip

    func flipCamera() {
        let newPosition: AVCaptureDevice.Position = cameraPosition == .back ? .front : .back
        cameraPosition = newPosition
        // Run session reconfiguration on a background thread — blocking main is not OK
        Task.detached(priority: .userInitiated) { [session = captureSession, position = newPosition] in
            session.beginConfiguration()
            session.inputs
                .compactMap { $0 as? AVCaptureDeviceInput }
                .filter { $0.device.hasMediaType(.video) }
                .forEach { session.removeInput($0) }

            if let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
               let input = try? AVCaptureDeviceInput(device: camera),
               session.canAddInput(input) {
                session.addInput(input)
            }
            session.commitConfiguration()
        }
    }

    // MARK: - Timer

    private func startTimer() {
        elapsedTime = 0
        // Scheduled from @MainActor context → fires on main RunLoop.
        // MainActor.assumeIsolated avoids the Task overhead of the previous pattern.
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.elapsedTime += 0.1
                self.updateDisplay()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateDisplay() {
        let total = Int(elapsedTime)
        displayTime = String(format: "%02d:%02d", total / 60, total % 60)

        switch state {
        case .recordingSegment1:
            progress = min(elapsedTime / maxSegmentDuration, 1.0) * 0.5
        case .recordingSegment2:
            let seg2 = max(elapsedTime - segment1Duration, 0)
            progress = 0.5 + min(seg2 / maxSegmentDuration, 1.0) * 0.5
        default:
            break
        }
    }

    // MARK: - Helpers

    private func cacheURL(_ filename: String) -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = dir.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
        return url
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension CameraService: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: (any Error)?
    ) {
        Task { @MainActor in
            let action = self.pendingAction
            self.pendingAction = .none
            switch action {
            case .startSegment2:
                self.startSegment2()
            case .finish:
                self.state = .completed
                if let url1 = self.segment1URL, let url2 = self.segment2URL {
                    self.onCompleted?(url1, url2)
                }
            case .none:
                break
            }
        }
    }
}
