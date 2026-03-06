import SwiftUI

struct ExportSettingsScreen: View {
    @EnvironmentObject private var flow: FlowState

    @State private var resolutionRaw  = Resolution.fhd1080.rawValue
    @State private var frameRateRaw   = "30fps"
    @State private var formatRaw      = OutputFormat.mp4.rawValue
    @State private var codecRaw       = VideoCodec.h264.rawValue
    @State private var includeQR      = true
    @State private var includeIcon    = true

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
                Text("Export Settings")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.top, 10)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)

            // ── Scrollable settings ─────────────────────────────────────
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    EmptyView().frame(height: 24)
                    // QUALITY
                    SettingsGroup("QUALITY") {
                        VStack(spacing: 0) {
                            SettingsChipRow(label: "Resolution",
                                           options: Resolution.allCases.map(\.rawValue),
                                           selected: $resolutionRaw)
                            InsetDivider()
                            SettingsChipRow(label: "Frame Rate",
                                           options: ["30fps", "60fps"],
                                           selected: $frameRateRaw)
                        }
                    }

                    // FORMAT & CODEC
                    SettingsGroup("FORMAT & CODEC") {
                        HStack(spacing: 12) {
                            DropdownRow(label: "File Format",
                                        options: OutputFormat.allCases.map(\.rawValue),
                                        selected: $formatRaw)
                            DropdownRow(label: "Codec",
                                        options: VideoCodec.allCases.map(\.rawValue),
                                        selected: $codecRaw)
                        }
                    }

                    // WATERMARK
                    SettingsGroup("WATERMARK") {
                        VStack(spacing: 0) {
                            WatermarkToggleRow(
                                systemIcon: "qrcode",
                                title: "App QR Code Overlay",
                                isOn: $includeQR
                            )
                            InsetDivider()
                            WatermarkToggleRow(
                                systemIcon: "app.badge.fill",
                                title: "App Icon Watermark",
                                isOn: $includeIcon
                            )
                        }
                    }

                    // Estimated file size
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Estimated File Size")
                                .font(.system(size: 14))
                                .foregroundColor(Color(hex: "8E8E93"))
                            Spacer()
                            Text(estimatedSize)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.appPrimary)
                        }
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color(hex: "8E8E93"))
                                .frame(width: 4, height: 4)
                            Text("Values are approximate based on recorded video length.")
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: "8E8E93"))
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }

            Spacer(minLength: 0)

            // ── Start Export button ─────────────────────────────────────
            Button(action: startExport) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Start Export")
                        .font(.system(size: 17, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Color.appPrimary)
                .foregroundColor(.white)
                .cornerRadius(14)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .background(Color.appBackground.ignoresSafeArea())
    }

    // MARK: - Helpers

    private var estimatedSize: String {
        let resolution = Resolution(rawValue: resolutionRaw) ?? .fhd1080
        let fps        = frameRateRaw == "60fps" ? 60 : 30
        let bitrate    = resolution.bitrate * fps / 30
        let seconds    = 60
        let bytes      = Int64(bitrate / 8) * Int64(seconds)
        return String(format: "%.1f MB", Double(bytes) / 1_000_000)
    }

    private func startExport() {
        var s = ExportSettings()
        s.resolution          = Resolution(rawValue: resolutionRaw)     ?? .fhd1080
        s.codec               = VideoCodec(rawValue: codecRaw)          ?? .h264
        s.frameRate           = frameRateRaw == "60fps" ? 60 : 30
        s.outputFormat        = OutputFormat(rawValue: formatRaw)       ?? .mp4
        s.includeQROverlay    = includeQR
        s.includeIconWatermark = includeIcon
        flow.settings = s
        flow.route = .processing
    }
}

// MARK: - SettingsGroup

private struct SettingsGroup<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(hex: "8E8E93"))
                .tracking(0.5)
            content
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - SettingsChipRow

private struct SettingsChipRow: View {
    let label: String
    let options: [String]
    @Binding var selected: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "8E8E93"))
            HStack(spacing: 0) {
                ForEach(options, id: \.self) { opt in
                    Button(action: { selected = opt }) {
                        Text(opt)
                            .font(.system(size: 14, weight: selected == opt ? .semibold : .regular))
                            .foregroundColor(selected == opt ? .white : Color(hex: "8E8E93"))
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(selected == opt
                                ? Color.white.opacity(0.12)
                                : Color.clear)
                    }
                }
            }
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - DropdownRow

private struct DropdownRow: View {
    let label: String
    let options: [String]
    @Binding var selected: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "8E8E93"))

            Menu {
                ForEach(options, id: \.self) { opt in
                    Button(opt) { selected = opt }
                }
            } label: {
                HStack {
                    Text(selected)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: "8E8E93"))
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(Color.white.opacity(0.08))
                .cornerRadius(8)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - WatermarkToggleRow

private struct WatermarkToggleRow: View {
    let systemIcon: String
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.appPrimary.opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: systemIcon)
                    .font(.system(size: 16))
                    .foregroundColor(.appPrimary)
            }
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(.appPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - InsetDivider

private struct InsetDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 0.5)
            .padding(.horizontal, 14)
    }
}
