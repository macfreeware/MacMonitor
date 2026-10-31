import SwiftUI

public struct MemoryDetailView: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var settings: AppSettings
    
    public init(monitor: SystemMonitor, settings: AppSettings) {
        self.monitor = monitor
        self.settings = settings
    }
    
    private var statusColor: Color {
        let pct = monitor.memoryInfo.usedPercentage
        if pct >= settings.ramAlertThreshold {
            return .red
        } else if pct >= 80.0 {
            return .orange
        } else {
            return .green
        }
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Label(settings.t("Bellek (RAM)", "Memory (RAM)"), systemImage: "memorychip")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(monitor.memoryInfo.formattedUsed) / \(monitor.memoryInfo.formattedTotal)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                
                Text(monitor.memoryInfo.formattedPercentage)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(statusColor)
            }
            
            // Segmented Distribution Bar
            GeometryReader { geo in
                let total = max(1.0, Double(monitor.memoryInfo.totalBytes))
                let w = geo.size.width
                let activeW = max(0, w * CGFloat(Double(monitor.memoryInfo.activeBytes) / total))
                let wiredW = max(0, w * CGFloat(Double(monitor.memoryInfo.wiredBytes) / total))
                let compW = max(0, w * CGFloat(Double(monitor.memoryInfo.compressedBytes) / total))
                let usedW = activeW + wiredW + compW
                let freeW = max(0, w - usedW)
                
                HStack(spacing: 1.5) {
                    // App / Active
                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: activeW)
                    
                    // Wired
                    Rectangle()
                        .fill(Color.purple)
                        .frame(width: wiredW)
                    
                    // Compressed
                    Rectangle()
                        .fill(Color.orange)
                        .frame(width: compW)
                    
                    // Free / Inactive
                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: freeW)
                }
                .frame(height: 8)
                .cornerRadius(4)
            }
            .frame(height: 8)
            
            // Memory Breakdown Legend with Tooltips
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                legendItem(
                    title: settings.t("Uygulamalar", "App Memory"),
                    value: monitor.memoryInfo.formattedActive,
                    color: .blue,
                    tooltip: settings.t(
                        "Aktif çalışan uygulamaların kullandığı bellek.",
                        "Memory currently used by active applications."
                    )
                )
                legendItem(
                    title: settings.t("Bağlı Sistem", "Wired Memory"),
                    value: monitor.memoryInfo.formattedWired,
                    color: .purple,
                    tooltip: settings.t(
                        "macOS çekirdeği ve donanım sürücülerinin kullandığı kilitli bellek (diske taşınamaz).",
                        "Locked memory used by the macOS kernel and drivers (cannot be paged out)."
                    )
                )
                legendItem(
                    title: settings.t("Sıkıştırılmış", "Compressed"),
                    value: monitor.memoryInfo.formattedCompressed,
                    color: .orange,
                    tooltip: settings.t(
                        "Arka plandaki uygulamaların RAM'de tutulan sıkıştırılmış verileri. Çöp değildir; SSD takasından kat kat daha hızlıdır.",
                        "Compressed inactive app data kept in RAM. Much faster than swapping to SSD."
                    )
                )
                legendItem(
                    title: settings.t("Boş / Önbellek", "Free / Cached"),
                    value: monitor.memoryInfo.formattedFree,
                    color: Color.primary.opacity(0.4),
                    tooltip: settings.t(
                        "Boş veya uygulamaların anında açılması için dosya önbelleği olarak tutulan alan.",
                        "Available RAM or cached files ready to be reclaimed instantly."
                    )
                )
            }
            
            // Swap Info
            HStack {
                Text(settings.t("Takas Alanı (Swap):", "Swap Used:"))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(monitor.memoryInfo.formattedSwap)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.primary)
            }
            .padding(.top, 2)
            .help(settings.t("RAM tamamen dolduğunda SSD'ye aktarılan sanal bellek miktarı.", "Virtual memory paged out to SSD when physical RAM is full."))
            
            // Educational Info Hint
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.system(size: 8.5))
                    .foregroundColor(.secondary)
                Text(settings.t("Sıkıştırılmış bellek, arka plan verilerini SSD yerine RAM'de hızlı tutar.", "Compressed memory keeps inactive data fast in RAM instead of SSD."))
                    .font(.system(size: 8.5))
                    .foregroundColor(.secondary)
            }
            
            // RAM History Graph
            if settings.showSparkline {
                VStack(alignment: .leading, spacing: 3) {
                    Text(settings.t("RAM Doluluk Geçmişi (Son 60 sn)", "RAM Usage History (Last 60s)"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    SparklineView(
                        data: monitor.memoryInfo.history,
                        strokeColor: statusColor,
                        fillColor: statusColor.opacity(0.18)
                    )
                    .frame(height: 38)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(6)
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
    
    private func legendItem(title: String, value: String, color: Color, tooltip: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            
            Text(title + ":")
                .font(.system(size: 10, weight: .regular))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
        }
        .help(tooltip)
    }
}
