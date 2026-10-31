import SwiftUI

public struct CPUDetailView: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var settings: AppSettings
    
    public init(monitor: SystemMonitor, settings: AppSettings) {
        self.monitor = monitor
        self.settings = settings
    }
    
    private var statusColor: Color {
        let usage = monitor.cpuInfo.totalUsage
        if usage >= settings.cpuAlertThreshold {
            return .red
        } else if usage >= 65.0 {
            return .orange
        } else {
            return .blue
        }
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Label(settings.t("İşlemci (CPU)", "Processor (CPU)"), systemImage: "cpu")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text(monitor.cpuInfo.formattedTotal)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(statusColor)
            }
            
            // Overall Usage Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [statusColor.opacity(0.8), statusColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(monitor.cpuInfo.totalUsage / 100.0))), height: 8)
                        .animation(.easeInOut(duration: 0.2), value: monitor.cpuInfo.totalUsage)
                }
            }
            .frame(height: 8)
            
            // User vs System vs Idle Breakdown
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Circle().fill(Color.blue).frame(width: 6, height: 6)
                    Text(settings.t("Kullanıcı:", "User:"))
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.secondary)
                    Text(monitor.cpuInfo.formattedUser)
                        .font(.system(size: 10, weight: .semibold))
                }
                
                HStack(spacing: 4) {
                    Circle().fill(Color.purple).frame(width: 6, height: 6)
                    Text(settings.t("Sistem:", "System:"))
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.secondary)
                    Text(monitor.cpuInfo.formattedSystem)
                        .font(.system(size: 10, weight: .semibold))
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    Circle().fill(Color.gray.opacity(0.5)).frame(width: 6, height: 6)
                    Text(settings.t("Boşta:", "Idle:"))
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.secondary)
                    Text(monitor.cpuInfo.formattedIdle)
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            
            // Per-Core Distribution (E-Cores & P-Cores)
            if !monitor.cpuInfo.coreUsages.isEmpty {
                let eCount = SystemInfoHelper.efficiencyCoreCount
                let pCount = SystemInfoHelper.performanceCoreCount
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(
                            eCount > 0
                                ? settings.t("Çekirdek Dağılımı (\(eCount)E + \(pCount)P)", "Core Distribution (\(eCount)E + \(pCount)P)")
                                : settings.t("Çekirdek Dağılımı (\(monitor.cpuInfo.coreUsages.count) Çekirdek)", "Core Distribution (\(monitor.cpuInfo.coreUsages.count) Cores)")
                        )
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        if eCount > 0 {
                            HStack(spacing: 8) {
                                HStack(spacing: 3) {
                                    Circle().fill(Color.teal).frame(width: 5, height: 5)
                                    Text(settings.t("E: Verimlilik", "E: Efficiency")).font(.system(size: 8.5)).foregroundColor(.secondary)
                                }
                                HStack(spacing: 3) {
                                    Circle().fill(Color.orange).frame(width: 5, height: 5)
                                    Text(settings.t("P: Performans", "P: Performance")).font(.system(size: 8.5)).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    
                    let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: min(monitor.cpuInfo.coreUsages.count, 8))
                    
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(Array(monitor.cpuInfo.coreUsages.enumerated()), id: \.offset) { index, usage in
                            let isECore = (eCount > 0 && index < eCount)
                            let coreLabel = isECore ? "E\(index + 1)" : (eCount > 0 ? "P\(index - eCount + 1)" : "C\(index + 1)")
                            let coreTagColor = isECore ? Color.teal : (eCount > 0 ? Color.orange : Color.blue)
                            let coreTooltip = isECore
                                ? settings.t(
                                    "E\(index + 1) Çekirdeği: Verimlilik (Düşük güç, arka plan işlemleri)",
                                    "Core E\(index + 1): Efficiency (Low power, background tasks)"
                                )
                                : settings.t(
                                    "P\(index - eCount + 1) Çekirdeği: Yüksek Performans (Ağır iş yükleri)",
                                    "Core P\(index - eCount + 1): High Performance (Heavy workloads)"
                                )
                            
                            VStack(spacing: 2) {
                                // Core Type Badge (E1.. or P1..)
                                Text(coreLabel)
                                    .font(.system(size: 8, weight: .bold, design: .rounded))
                                    .foregroundColor(coreTagColor)
                                
                                // Vertical Level Bar
                                GeometryReader { coreGeo in
                                    ZStack(alignment: .bottom) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color.primary.opacity(0.08))
                                            .frame(width: coreGeo.size.width, height: 26)
                                        
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(coreBarColor(usage: usage, isECore: isECore))
                                            .frame(width: coreGeo.size.width, height: max(2, 26 * CGFloat(usage / 100.0)))
                                            .animation(.easeInOut(duration: 0.2), value: usage)
                                    }
                                }
                                .frame(height: 26)
                                
                                Text("\(Int(usage))%")
                                    .font(.system(size: 7.5, weight: .medium, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                            .help(coreTooltip)
                        }
                    }
                }
            }
            
            // Live History Graph
            if settings.showSparkline {
                VStack(alignment: .leading, spacing: 3) {
                    Text(settings.t("CPU Yük Geçmişi (Son 60 sn)", "CPU Load History (Last 60s)"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    SparklineView(
                        data: monitor.cpuInfo.history,
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
    
    private func coreBarColor(usage: Double, isECore: Bool) -> Color {
        if usage >= 85.0 {
            return .red
        } else if usage >= 60.0 {
            return .orange
        } else if isECore {
            return .teal
        } else {
            return .blue
        }
    }
}
