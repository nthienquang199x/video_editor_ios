import SwiftUI
import AVFoundation

struct CameraScreen: View {
    @EnvironmentObject private var flow: FlowState
    @StateObject private var camera = CameraService()
    @State private var showPermissionAlert = false

    private var isRecording: Bool {
        camera.state == .recordingSegment1 || camera.state == .recordingSegment2
    }

    private var segmentLabel: String {
        switch camera.state {
        case .idle, .recordingSegment1: return "Segment 1 of 2"
        case .recordingSegment2:        return "Segment 2 of 2"
        case .completed:                return "Complete"
        }
    }

    var body: some View {
        ZStack {
            // Full-screen camera preview
            CameraPreviewView(session: camera.captureSession)
                .ignoresSafeArea()

            // UI overlay
            VStack(spacing: 0) {

                // Top HUD: timer + progress bar
                VStack(spacing: 8) {
                    TimerPill(time: camera.displayTime)
                    RecordingProgressBar(progress: camera.progress)
                }
                .padding(.top, 52)

                Spacer()

                // Center: focus brackets + segment label
                VStack(spacing: 14) {
                    FocusBrackets()
                        .frame(width: 230, height: 290)

                    Text(segmentLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.45))
                        .clipShape(Capsule())
                }

                Spacer()

                // Bottom controls
                ZStack(alignment: .center) {
                    // Center: record button + label
                    VStack(spacing: 6) {
                        RecordButton(isRecording: isRecording, onTap: camera.handleRecordButton)
                        Text("Video")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.65))
                    }

                    // Right: flip camera button
                    HStack {
                        Spacer()
                        Button(action: camera.flipCamera) {
                            Image(systemName: "camera.rotate.fill")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 46, height: 46)
                                .background(Color.white.opacity(0.15))
                                .clipShape(Circle())
                        }
                        .padding(.trailing, 36)
                    }
                }
                .padding(.bottom, 50)
            }
        }
        .onAppear {
            requestPermissions {
                camera.setupSession()
                camera.startSession()
            }
            camera.onCompleted = { url1, url2 in
                flow.segments = RecordedSegments(video1URL: url1, video2URL: url2)
                flow.route = .exportSettings
            }
        }
        .onDisappear {
            camera.stopSession()
        }
        .alert("Camera Access Required", isPresented: $showPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please allow camera and microphone access to record video.")
        }
    }

    private func requestPermissions(completion: @escaping () -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { videoOK in
            guard videoOK else {
                Task { @MainActor in self.showPermissionAlert = true }
                return
            }
            AVCaptureDevice.requestAccess(for: .audio) { audioOK in
                guard audioOK else {
                    Task { @MainActor in self.showPermissionAlert = true }
                    return
                }
                Task { @MainActor in completion() }
            }
        }
    }
}

// MARK: - RecordingProgressBar

private struct RecordingProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 3)
                Capsule()
                    .fill(Color.appPrimary)
                    .frame(width: geo.size.width * progress, height: 3)
                    .animation(.linear(duration: 0.15), value: progress)
                // Mid divider
                Rectangle()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: 1.5, height: 8)
                    .offset(x: geo.size.width / 2 - 0.75)
            }
            .frame(height: 8, alignment: .center)
        }
        .frame(height: 8)
        .padding(.horizontal, 20)
    }
}

// MARK: - TimerPill

private struct TimerPill: View {
    let time: String

    var body: some View {
        Text(time)
            .font(.system(size: 14, weight: .semibold, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.55))
            .clipShape(Capsule())
    }
}

// MARK: - FocusBrackets

private struct FocusBrackets: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let arm: CGFloat = 22
            let lw:  CGFloat = 2.5

            ZStack {
                corner(at: CGPoint(x: 0, y: 0),  armX:  arm, armY:  arm, lw: lw)
                corner(at: CGPoint(x: w, y: 0),  armX: -arm, armY:  arm, lw: lw)
                corner(at: CGPoint(x: 0, y: h),  armX:  arm, armY: -arm, lw: lw)
                corner(at: CGPoint(x: w, y: h),  armX: -arm, armY: -arm, lw: lw)
            }
        }
    }

    private func corner(at p: CGPoint, armX: CGFloat, armY: CGFloat, lw: CGFloat) -> some View {
        Path { path in
            path.move(to: CGPoint(x: p.x,        y: p.y + armY))
            path.addLine(to: p)
            path.addLine(to: CGPoint(x: p.x + armX, y: p.y))
        }
        .stroke(Color.appPrimary, style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
    }
}

// MARK: - RecordButton

private struct RecordButton: View {
    let isRecording: Bool
    let onTap: () -> Void

    @State private var pulse = false

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Animated outer ring when recording
                if isRecording {
                    Circle()
                        .stroke(Color.white.opacity(pulse ? 0.2 : 0.65), lineWidth: pulse ? 2 : 4)
                        .frame(width: pulse ? 98 : 86, height: pulse ? 98 : 86)
                        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
                }
                // Static outer ring
                Circle()
                    .stroke(Color.white, lineWidth: 3)
                    .frame(width: 80, height: 80)
                // Inner fill
                RoundedRectangle(cornerRadius: isRecording ? 8 : 38)
                    .fill(Color.white)
                    .frame(width: isRecording ? 32 : 62, height: isRecording ? 32 : 62)
                    .animation(.spring(response: 0.3), value: isRecording)
            }
        }
        .onChange(of: isRecording) { _, newVal in pulse = newVal }
        .onAppear { pulse = isRecording }
    }
}
