import SwiftUI
import AVKit
import Photos

struct ExportCompleteScreen: View {
    @EnvironmentObject private var flow: FlowState
    @State private var savedToGallery = false
    @State private var saveError: String?
    @State private var showShareSheet = false
    @State private var player: AVPlayer?

    private var outputURL: URL? { flow.outputURL }

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ──────────────────────────────────────────────────
            ZStack {
                HStack {
                    Button(action: { flow.route = .camera }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    Spacer()
                }
                Text("Export Complete")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.top, 10)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {

                    // ── Video player ────────────────────────────────────
                    if let player {
                        VideoPlayer(player: player)
                            .frame(height: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .padding(.horizontal, 20)
                    } else {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white.opacity(0.06))
                            .frame(height: 240)
                            .overlay(
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 48))
                                    .foregroundColor(.white.opacity(0.4))
                            )
                            .padding(.horizontal, 20)
                    }

                    // ── Success content ─────────────────────────────────
                    VStack(spacing: 12) {
                        // Green checkmark
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.15))
                                .frame(width: 52, height: 52)
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.green)
                        }

                        Text("Your video is ready!")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)

                        Text("High resolution export finished. The watermark includes your unique QR code for instant viewing.")
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "8E8E93"))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    .padding(.horizontal, 20)

                    // ── Action buttons ──────────────────────────────────
                    VStack(spacing: 10) {
                        if let err = saveError {
                            Text(err)
                                .font(.system(size: 12))
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                        }

                        // Save to Gallery
                        Button(action: saveToGallery) {
                            HStack(spacing: 8) {
                                Image(systemName: savedToGallery
                                      ? "checkmark.circle.fill"
                                      : "arrow.down.to.line.circle")
                                    .font(.system(size: 16))
                                Text(savedToGallery ? "Saved to Gallery" : "Save to Gallery")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(savedToGallery ? Color.green : Color.appPrimary)
                            .foregroundColor(.white)
                            .cornerRadius(14)
                            .animation(.spring(response: 0.3), value: savedToGallery)
                        }
                        .disabled(savedToGallery)

                        // Share
                        Button(action: { showShareSheet = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 16))
                                Text("Share Project")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.white.opacity(0.10))
                            .foregroundColor(.white)
                            .cornerRadius(14)
                        }
                    }
                    .padding(.horizontal, 20)

                    // ── File info (no card background) ──────────────────
                    VStack(spacing: 0) {
                        fileInfoRow(label: "File Size",
                                    value: formatSize(flow.fileSizeBytes))
                        Divider().background(Color.white.opacity(0.08))

                        fileInfoRow(label: "Resolution",
                                    value: "\(flow.settings.resolution.rawValue) (\(resolutionLabel))")
                        Divider().background(Color.white.opacity(0.08))

                        fileInfoRow(label: "Format",
                                    value: "MP4 (\(flow.settings.codec.rawValue))")
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                    // Record again (subtle)
                    Button(action: { flow.route = .camera }) {
                        Text("Record Again")
                            .font(.system(size: 15))
                            .foregroundColor(Color(hex: "636366"))
                    }
                    .padding(.bottom, 32)
                }
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .sheet(isPresented: $showShareSheet) {
            if let url = outputURL {
                ShareSheet(items: [url])
            }
        }
        .onAppear {
            if let url = outputURL {
                player = AVPlayer(url: url)
            }
        }
        .onDisappear { player?.pause() }
    }

    // MARK: - File info row

    private func fileInfoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "8E8E93"))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.vertical, 13)
    }

    // MARK: - Helpers

    private var resolutionLabel: String {
        switch flow.settings.resolution {
        case .hd720:   return "720p"
        case .fhd1080: return "1080p"
        case .uhd4k:   return "2160p"
        }
    }

    private func saveToGallery() {
        guard let url = outputURL else { return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in
                    self.saveError = "Photo library access denied. Enable in Settings."
                }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { success, error in
                Task { @MainActor in
                    if success {
                        self.savedToGallery = true
                        self.saveError = nil
                    } else {
                        self.saveError = error?.localizedDescription ?? "Failed to save."
                    }
                }
            }
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_000_000
        if mb < 1    { return "\(bytes) B" }
        if mb < 1000 { return String(format: "%.1f MB", mb) }
        return String(format: "%.2f GB", mb / 1000)
    }
}

// MARK: - ShareSheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
