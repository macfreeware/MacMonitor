import SwiftUI
import AppKit

public extension Notification.Name {
    static let closeMacMonitorPopover = Notification.Name("closeMacMonitorPopover")
}

@MainActor
public final class AboutWindowManager: NSObject, NSWindowDelegate {
    public static let shared = AboutWindowManager()
    
    private var window: NSWindow?
    
    private override init() {
        super.init()
    }
    
    public func show() {
        // Close popover so the standalone About window is cleanly focused
        NotificationCenter.default.post(name: .closeMacMonitorPopover, object: nil)
        
        if let existingWindow = window {
            existingWindow.title = AppSettings.shared.t("MacMonitor Hakkında", "About MacMonitor")
            if let hc = existingWindow.contentViewController as? NSHostingController<AboutWindowView> {
                let fitSize = hc.sizeThatFits(in: NSSize(width: 420, height: 2000))
                existingWindow.setContentSize(NSSize(width: 420, height: ceil(fitSize.height)))
            }
            NSApp.activate(ignoringOtherApps: true)
            existingWindow.makeKeyAndOrderFront(nil)
            existingWindow.orderFrontRegardless()
            return
        }
        
        let aboutView = AboutWindowView { [weak self] in
            self?.close()
        }
        let hostingController = NSHostingController(rootView: aboutView)
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 540),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = AppSettings.shared.t("MacMonitor Hakkında", "About MacMonitor")
        newWindow.titlebarAppearsTransparent = false
        newWindow.titleVisibility = .visible
        newWindow.isMovableByWindowBackground = true
        newWindow.isReleasedWhenClosed = false
        newWindow.level = .floating
        newWindow.backgroundColor = .windowBackgroundColor
        newWindow.isOpaque = true
        newWindow.hasShadow = true
        newWindow.delegate = self
        newWindow.contentViewController = hostingController
        
        let fitSize = hostingController.sizeThatFits(in: NSSize(width: 420, height: 2000))
        newWindow.setContentSize(NSSize(width: 420, height: ceil(fitSize.height)))
        newWindow.center()
        
        self.window = newWindow
        
        NSApp.activate(ignoringOtherApps: true)
        newWindow.makeKeyAndOrderFront(nil)
        newWindow.orderFrontRegardless()
        newWindow.makeFirstResponder(nil)
    }
    
    public func close() {
        window?.close()
    }
}

public struct AboutWindowView: View {
    @ObservedObject private var settings: AppSettings = AppSettings.shared
    public var onClose: () -> Void
    
    private var osVersionString: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
    
    private var coreSummaryString: String {
        let total = SystemInfoHelper.coreCount
        let eCores = SystemInfoHelper.efficiencyCoreCount
        let pCores = SystemInfoHelper.performanceCoreCount
        if eCores > 0 {
            return settings.t(
                "\(total) Çekirdek (\(pCores) Performans + \(eCores) Verimlilik)",
                "\(total) Cores (\(pCores) Performance + \(eCores) Efficiency)"
            )
        }
        return settings.t("\(total) Mantıksal Çekirdek", "\(total) Logical Cores")
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            // Top Hero Section
            VStack(spacing: 10) {
                AppLogoBadgeView(size: 68, showGlow: true)
                    .padding(.top, 4)
                
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Text("MacMonitor")
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                        
                        Text("v1.0.4")
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            .foregroundColor(.cyan)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.cyan.opacity(0.14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.cyan.opacity(0.35), lineWidth: 1)
                            )
                            .cornerRadius(8)
                    }
                    
                    Text(settings.t(
                        "Ultra Hafif, Sıfır Log Üreten Sistem Kaynak Monitörü",
                        "Ultra-Lightweight, Zero-Log System Resource Monitor"
                    ))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    // Developer & License Badges
                    HStack(spacing: 8) {
                        HStack(spacing: 5) {
                            Image(systemName: "person.crop.circle.fill.badge.checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.accentColor)
                            Text(settings.t("Geliştirici:", "Developer:"))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                            Text("Rafet Sapancı")
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                        .cornerRadius(12)
                        
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundColor(.green)
                            Text("GNU GPL v3.0")
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.green.opacity(0.3), lineWidth: 1)
                        )
                        .cornerRadius(12)
                    }
                    .padding(.top, 2)
                }
            }
            
            Divider()
            
            // Hardware & System Summary Card
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "macbook.and.iphone")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.accentColor)
                    Text(settings.t("BU MAC'İN DONANIM ÖZETİ", "HARDWARE SUMMARY OF THIS MAC"))
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(.secondary)
                }
                
                VStack(spacing: 7) {
                    hardwareRow(icon: "cpu", label: settings.t("İşlemci", "Processor"), value: SystemInfoHelper.cpuBrand)
                    hardwareRow(icon: "square.grid.3x3.topleft.filled", label: settings.t("Çekirdek Yapısı", "Core Layout"), value: coreSummaryString)
                    hardwareRow(
                        icon: "memorychip",
                        label: settings.t("Fiziksel Bellek (RAM)", "Physical Memory (RAM)"),
                        value: settings.t(
                            "\(SystemInfoHelper.formatGB(SystemInfoHelper.totalPhysicalMemory)) Birleşik Bellek",
                            "\(SystemInfoHelper.formatGB(SystemInfoHelper.totalPhysicalMemory)) Unified Memory"
                        )
                    )
                    hardwareRow(icon: "apple.logo", label: settings.t("İşletim Sistemi", "Operating System"), value: osVersionString)
                    hardwareRow(icon: "clock.badge.checkmark", label: settings.t("Açık Kalma Süresi", "System Uptime"), value: SystemInfoHelper.formattedUptime)
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.65))
                .cornerRadius(9)
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
            
            // Technical Architecture Highlights
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.orange)
                    Text(settings.t("MİMARİ VE PERFORMANS ÖZELLİKLERİ", "ARCHITECTURE & PERFORMANCE FEATURES"))
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    featureItem(
                        icon: "bolt.shield.fill",
                        color: .green,
                        title: settings.t("Sıfır Sistem Logu (Zero-Log Architecture)", "Zero System Logs (Zero-Log Architecture)"),
                        subtitle: settings.t(
                            "Arka planda top, ps veya vm_stat gibi kabuk süreçleri başlatmaz; macOS Console ve system.log kayıtlarını şişirmez.",
                            "Does not spawn shell subprocesses like top, ps, or vm_stat; never pollutes macOS Console or system.log."
                        )
                    )
                    
                    Divider().opacity(0.5)
                    
                    featureItem(
                        icon: "memorychip.fill",
                        color: .blue,
                        title: settings.t("Doğrudan Darwin Mach Kernel C API", "Direct Darwin Mach Kernel C API"),
                        subtitle: settings.t(
                            "host_statistics64, host_processor_info ve libproc çekirdek çağrıları ile ~%0.05 CPU tüketimiyle çalışır.",
                            "Uses native host_statistics64, host_processor_info, and libproc kernel calls with ~0.05% CPU overhead."
                        )
                    )
                    
                    Divider().opacity(0.5)
                    
                    featureItem(
                        icon: "cpu.fill",
                        color: .purple,
                        title: settings.t("Apple Silicon E-Core & P-Core Analizi", "Apple Silicon E-Core & P-Core Analytics"),
                        subtitle: settings.t(
                            "Verimlilik (Efficiency) ve Performans çekirdeklerini, uygulama/wired/sıkıştırılmış RAM dağılımını gerçek zamanlı izler.",
                            "Monitors Efficiency and Performance cores as well as App, Wired, and Compressed RAM in real time."
                        )
                    )
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.65))
                .cornerRadius(9)
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
            
            // GNU License Section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                        Text(settings.t("AÇIK KAYNAK VE LİSANS BİLGİSİ", "OPEN SOURCE & LICENSE INFO"))
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        if let url = URL(string: "https://www.gnu.org/licenses/gpl-3.0.html") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 3) {
                            Text(settings.t("Lisans Metni (GPLv3)", "License Text (GPLv3)"))
                            Image(systemName: "arrow.up.right.square")
                        }
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("GNU General Public License v3.0 (GPL-3.0)")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text(settings.t(
                        "Bu program özgür yazılımdır; Özgür Yazılım Vakfı (Free Software Foundation) tarafından yayınlanan GNU Genel Kamu Lisansı 3. sürümü (veya sonraki sürümleri) koşulları altında özgürce yeniden dağıtabilir ve/veya değiştirebilirsiniz.",
                        "This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version."
                    ))
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.65))
                .cornerRadius(9)
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
            
            // Footer
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(settings.t(
                        "© 2026 Rafet Sapancı • GNU GPL v3.0 Açık Kaynak Lisansı",
                        "© 2026 Rafet Sapancı • GNU GPL v3.0 Open Source License"
                    ))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.primary.opacity(0.85))
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("SwiftUI • AppKit • Darwin Mach Kernel")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button(action: onClose) {
                    Text(settings.t("Kapat", "Close"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                .keyboardShortcut(.cancelAction)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 18)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func hardwareRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 16, alignment: .center)
            
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
    }
    
    private func featureItem(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 22, height: 22)
                .background(color.opacity(0.14))
                .cornerRadius(6)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
