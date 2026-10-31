import SwiftUI
import AppKit

public struct ProcessListView: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var settings: AppSettings = AppSettings.shared
    @State private var selectedTab: Int = 0 // 0: CPU, 1: RAM
    
    public init(monitor: SystemMonitor) {
        self.monitor = monitor
    }
    
    public var body: some View {
        VStack(spacing: 8) {
            // Segmented Picker
            Picker("", selection: $selectedTab) {
                Text(settings.t("En Çok CPU", "Top CPU")).tag(0)
                Text(settings.t("En Çok RAM", "Top RAM")).tag(1)
            }
            .pickerStyle(SegmentedPickerStyle())
            
            // Process List Rows
            let items = selectedTab == 0 ? monitor.topCPUProcesses : monitor.topMemoryProcesses
            
            if items.isEmpty {
                VStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text(settings.t("İşlemler analiz ediliyor...", "Analyzing processes..."))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                VStack(spacing: 4) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, proc in
                        HStack(spacing: 8) {
                            Text("\(index + 1)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(.secondary)
                                .frame(width: 14, alignment: .leading)
                            
                            VStack(alignment: .leading, spacing: 1) {
                                Text(proc.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                
                                Text(verbatim: "PID: \(proc.pid)")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if selectedTab == 0 {
                                Text(proc.cpuFormatted)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundColor(proc.cpuPercent > 30 ? .red : (proc.cpuPercent > 10 ? .orange : .primary))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.primary.opacity(0.06))
                                    .cornerRadius(4)
                            } else {
                                Text(proc.memFormatted)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.primary.opacity(0.06))
                                    .cornerRadius(4)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(index % 2 == 0 ? Color.primary.opacity(0.02) : Color.clear)
                        .cornerRadius(6)
                    }
                }
            }
            
            Divider()
                .padding(.vertical, 2)
            
            // Footer: Open Activity Monitor Shortcut
            HStack {
                Text(settings.t("⚡ Sadece pencere açıkken taranır", "⚡ Scanned only while window is open"))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: openActivityMonitor) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.forward.app")
                        Text(settings.t("Etkinlik Monitörü", "Activity Monitor"))
                    }
                    .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(BorderlessButtonStyle())
                .foregroundColor(.accentColor)
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
    
    private func openActivityMonitor() {
        let path = "/System/Applications/Utilities/Activity Monitor.app"
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
    }
}
