import SwiftUI
import AVFoundation

struct ProcessingScreen: View {
    @EnvironmentObject private var flow: FlowState
    @StateObject private var processor = VideoProcessor()

    @State private var thumb1: UIImage?
    @State private var thumb2: UIImage?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ──────────────────────────────────────────────────
            ZStack {
                HStack {
                    Button(action: {
                        processor.cancel()
                        flow.route = .camera
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }
                    Spacer()
                }
                Text("Merging Videos")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 20)
            .padding(.top, 60)
            .padding(.bottom, 24)

            // ── Staggered thumbnails ────────────────────────────────────
            StaggeredThumbnails(thumb1: thumb1, thumb2: thumb2)
                .frame(height: 210)
                .padding(.horizontal, 20)
                .padding(.bottom, 28)

            // ── Status + Progress ───────────────────────────────────────
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Joining clips...")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                        Text("Processing high-quality export")
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: "8E8E93"))
                    }
                    Spacer()
                    Text("\(Int(processor.progress * 100))%")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.appPrimary)
                }

                ProgressView(value: processor.progress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .appPrimary))
                    .scaleEffect(x: 1, y: 1.6, anchor: .center)

                // Estimated time
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "8E8E93"))
                    Text("Estimated time: calculating...")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "8E8E93"))
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            // ── Warning card ────────────────────────────────────────────
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.appPrimary.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: "info")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.appPrimary)
                }
                Text("Please keep the app active and do not lock your screen. Closing the app now will cancel the merge process.")
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: "8E8E93"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(Color.appPrimary.opacity(0.08))
            .cornerRadius(12)
            .padding(.horizontal, 20)

            if let err = errorMessage {
                Text(err)
                    .font(.system(size: 13))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }

            Spacer()

            // ── Cancel button ───────────────────────────────────────────
            Button(action: {
                processor.cancel()
                flow.route = .camera
            }) {
                Text("Cancel Process")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(14)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            // Spec line
            Text("\(flow.settings.resolution.rawValue) • \(flow.settings.frameRate)fps • \(flow.settings.codec.rawValue)")
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "636366"))
                .padding(.bottom, 32)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .onAppear {
            loadThumbnails()
            startProcessing()
        }
    }

    // MARK: - Thumbnails

    private func loadThumbnails() {
        guard let segs = flow.segments else { return }
        thumb1 = thumbnail(from: segs.video1URL)
        thumb2 = thumbnail(from: segs.video2URL)
    }

    private func thumbnail(from url: URL) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let gen   = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 400, height: 300)
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        guard let cgImage = try? gen.copyCGImage(at: time, actualTime: nil) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - Processing

    private func startProcessing() {
        guard let segs = flow.segments else {
            flow.route = .camera
            return
        }
        processor.process(
            segment1URL: segs.video1URL,
            segment2URL: segs.video2URL,
            settings: flow.settings
        ) { result in
            switch result {
            case .success(let (url, size)):
                flow.outputURL     = url
                flow.fileSizeBytes = size
                flow.route         = .exportComplete
            case .failure(let error):
                self.errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - StaggeredThumbnails

private struct StaggeredThumbnails: View {
    let thumb1: UIImage?
    let thumb2: UIImage?

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Segment 01 — upper left
            ThumbCard(image: thumb1, label: "Segment 01")
                .frame(width: 220, height: 138)
                .offset(x: 0, y: 0)

            // Segment 02 — lower right
            ThumbCard(image: thumb2, label: "Segment 02")
                .frame(width: 220, height: 138)
                .offset(x: 80, y: 70)

            // Go badge
            ZStack {
                Circle()
                    .fill(Color.appPrimary)
                    .frame(width: 36, height: 36)
                    .shadow(color: Color.appPrimary.opacity(0.5), radius: 6)
                Text("GO")
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(.white)
            }
            .offset(x: 200, y: 52)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ThumbCard: View {
    let image: UIImage?
    let label: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            Image(systemName: "video.fill")
                                .font(.system(size: 26))
                                .foregroundColor(Color(hex: "636366"))
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.35), radius: 8, y: 4)

            // Label badge
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .padding(8)
        }
    }
}
