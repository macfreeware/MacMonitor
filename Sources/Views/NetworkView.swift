import SwiftUI

public struct NetworkView: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var settings: AppSettings

    public init(monitor: SystemMonitor, settings: AppSettings) {
        self.monitor = monitor
        self.settings = settings
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            liveCard
            NetworkHistoryView(settings: settings)

            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.system(size: 8.5))
                    .foregroundColor(.secondary)
                Text(settings.t("Wi-Fi ve Ethernet, MacMonitor açıkken sayılır; veriler bu Mac'te kalır.",
                                "Wi-Fi and Ethernet, counted while MacMonitor runs; data stays on this Mac."))
                    .font(.system(size: 8.5))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private var liveCard: some View {
        let info = monitor.networkInfo
        let peak = max(info.downHistory.max() ?? 0, info.upHistory.max() ?? 0, 1000)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                speed(symbol: "arrow.down", title: settings.t("İndirme", "Download"),
                      value: info.downBytesPerSecond, color: NetworkColors.down)
                speed(symbol: "arrow.up", title: settings.t("Yükleme", "Upload"),
                      value: info.upBytesPerSecond, color: NetworkColors.up)
            }
            ZStack {
                SparklineView(data: info.downHistory, maxVal: peak,
                              strokeColor: NetworkColors.down, fillColor: NetworkColors.down.opacity(0.18))
                SparklineView(data: info.upHistory, maxVal: peak,
                              strokeColor: NetworkColors.up, fillColor: NetworkColors.up.opacity(0.12))
            }
            .frame(height: 38)
            Text(settings.t("Son 60 sn · en yüksek ", "Last 60 s · peak ")
                 + settings.formatSpeed(peak))
                .font(.system(size: 9.5))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }

    private func speed(symbol: String, title: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(title, systemImage: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(color)
            Text(settings.formatSpeed(value))
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The same two colors in the Network tab and the menu bar
enum NetworkColors {
    static let downNS = NSColor.systemBlue
    /// System orange is hard to read on a light menu bar, so light mode gets a darker shade
    static let upNS = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? .systemOrange
            : NSColor(srgbRed: 0.76, green: 0.34, blue: 0, alpha: 1)
    }
    static let down = Color(nsColor: downNS)
    static let up = Color(nsColor: upNS)
}
