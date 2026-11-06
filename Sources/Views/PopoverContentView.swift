import SwiftUI
import AppKit

public struct PopoverContentView: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var settings: AppSettings
    public var onHeightChange: ((CGFloat) -> Void)? = nil
    
    public init(monitor: SystemMonitor, settings: AppSettings, onHeightChange: ((CGFloat) -> Void)? = nil) {
        self.monitor = monitor
        self.settings = settings
        self.onHeightChange = onHeightChange
    }
    
    public var body: some View {
        let hasAlert = monitor.isCpuAlert || monitor.isRamAlert
        
        VStack(alignment: .leading, spacing: 0) {
            // Header Bar with App Logo Badge
            HStack(alignment: .center, spacing: 10) {
                // Custom App Icon Badge
                AppLogoBadgeView(size: 34, showGlow: true)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("MacMonitor")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                        
                        // Live Status indicator pill
                        HStack(spacing: 4) {
                            Circle()
                                .fill(hasAlert ? Color.red : Color.green)
                                .frame(width: 6, height: 6)
                            Text(hasAlert ? settings.t("Yüksek Yük", "High Load") : settings.t("Normal", "Normal"))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(hasAlert ? .red : .secondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(hasAlert ? Color.red.opacity(0.12) : Color.primary.opacity(0.06))
                        .cornerRadius(10)
                    }
                    
                    HStack(spacing: 4) {
                        Text(SystemInfoHelper.cpuBrand)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("•")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary.opacity(0.6))
                        Image(systemName: "clock")
                            .font(.system(size: 8.5))
                            .foregroundColor(.secondary)
                        Text(SystemInfoHelper.formattedUptime)
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                HStack(spacing: 6) {
                    // Refresh Button (Focus-ring free)
                    HeaderCircleIconButton(
                        systemName: "arrow.clockwise",
                        tooltip: settings.t("Hemen Yenile", "Refresh Now")
                    ) {
                        monitor.refreshMetrics()
                    }
                    
                    // Standalone About Window Button (Focus-ring free)
                    HeaderCircleIconButton(
                        systemName: "info.circle",
                        tooltip: settings.t("MacMonitor Hakkında", "About MacMonitor")
                    ) {
                        AboutWindowManager.shared.show()
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)
            
            // Tab Switcher
            // A segmented Picker sizes every segment to the widest label and, with four tabs,
            // grows past the popover width; this bar always splits the available width evenly
            PopoverTabBar(selection: $settings.activeTab, tabs: [
                (0, settings.t("Genel", "Overview")),
                (1, settings.t("İşlemler", "Processes")),
                (3, settings.t("Disk", "Disk")),
                (5, settings.t("Ağ", "Network")),
            ] + (BatteryInfo.isPresent ? [(4, settings.t("Pil", "Battery"))] : []) + [
                (2, settings.t("Ayarlar", "Settings")),
            ])
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
            
            Divider()
            
            // Content Area
            if settings.activeTab == 0 {
                // Overview: CPU & Memory cards
                VStack(spacing: 12) {
                    CPUDetailView(monitor: monitor, settings: settings)
                    MemoryDetailView(monitor: monitor, settings: settings)
                }
                .padding(14)
            } else if settings.activeTab == 1 {
                // Processes
                ProcessListView(monitor: monitor)
                    .padding(14)
            } else if settings.activeTab == 3 {
                // Disk space
                DiskView(settings: settings)
                    .padding(14)
            } else if settings.activeTab == 5 {
                // Network speed and usage
                NetworkView(monitor: monitor, settings: settings)
                    .padding(14)
            } else if settings.activeTab == 4 && BatteryInfo.isPresent {
                // Battery (only on Macs that have one)
                BatteryView(settings: settings)
                    .padding(14)
            } else {
                // Settings
                SettingsView(settings: settings)
                    .padding(14)
            }
        }
        .frame(width: 350)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        onHeightChange?(ceil(geo.size.height))
                    }
                    .onChange(of: geo.size.height) { newHeight in
                        onHeightChange?(ceil(newHeight))
                    }
            }
        )
        .background(VisualEffectBlur(material: .popover, blendingMode: .behindWindow))
        .contextMenu {
            Button(action: {
                AboutWindowManager.shared.show()
            }) {
                Label(settings.t("Hakkında Penceresini Aç...", "Open About Window..."), systemImage: "info.circle")
            }
            
            Button(action: {
                monitor.refreshMetrics()
            }) {
                Label(settings.t("Şimdi Yenile", "Refresh Now"), systemImage: "arrow.clockwise")
            }
            
            Divider()
            
            Button(action: {
                let path = "/System/Applications/Utilities/Activity Monitor.app"
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
            }) {
                Label(settings.t("Etkinlik Monitörünü Aç...", "Open Activity Monitor..."), systemImage: "waveform.path.ecg.rectangle")
            }
        }
    }
}

private struct PopoverTabBar: View {
    @Binding var selection: Int
    let tabs: [(tag: Int, title: String)]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs, id: \.tag) { tab in
                let isSelected = selection == tab.tag
                Text(tab.title)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isSelected ? Color(NSColor.controlBackgroundColor) : Color.clear)
                            .shadow(color: .black.opacity(isSelected ? 0.15 : 0), radius: 1, y: 0.5)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { selection = tab.tag }
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.primary.opacity(0.07))
        )
    }
}

private struct HeaderCircleIconButton: View {
    let systemName: String
    let tooltip: String
    let action: () -> Void
    @State private var isHovered: Bool = false
    
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(isHovered ? .primary : .secondary)
            .frame(width: 24, height: 24)
            .background(Color.primary.opacity(isHovered ? 0.12 : 0.06))
            .clipShape(Circle())
            .contentShape(Circle())
            .onHover { hovering in
                isHovered = hovering
            }
            .onTapGesture {
                action()
            }
            .help(tooltip)
    }
}

// Native macOS Visual Effect View for clean blur
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
