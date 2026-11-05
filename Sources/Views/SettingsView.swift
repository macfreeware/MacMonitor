import SwiftUI

public struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var isConfirmingQuit: Bool = false
    @State private var canConfirmQuit: Bool = false
    @State private var quitResetTask: Task<Void, Never>? = nil
    
    public init(settings: AppSettings) {
        self.settings = settings
    }
    
    public var body: some View {
        let isTR = settings.isTurkish
        
        VStack(alignment: .leading, spacing: 10) {
            // Section 1: Yenileme Hızı
            settingSection(title: settings.t("YENİLEME VE PERFORMANS", "REFRESH & PERFORMANCE")) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(settings.t("Yenileme Sıklığı", "Refresh Interval"))
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Picker("", selection: $settings.refreshInterval) {
                            Text(settings.t("0,5 sn (Canlı)", "0.5s (Live)")).tag(0.5)
                            Text(settings.t("1 sn (Hızlı)", "1s (Fast)")).tag(1.0)
                            Text(settings.t("2 sn (Önerilen)", "2s (Recommended)")).tag(2.0)
                            Text(settings.t("3 sn (Hafif)", "3s (Light)")).tag(3.0)
                            Text(settings.t("5 sn (Ultra Eko)", "5s (Ultra Eco)")).tag(5.0)
                        }
                        .frame(width: 145)
                    }
                    
                    Text(settings.t(
                        "💡 Panel kapalıyken 2 sn'de ~%0,3, 0,5 sn'de ~%0,9 CPU; sistem logu üretmez.",
                        "💡 With the panel closed: ~0.3% CPU at 2s, ~0.9% at 0.5s; no system logs."
                    ))
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                }
            }
            
            // Section 2: Menü Çubuğu Görünümü
            settingSection(title: settings.t("MENÜ ÇUBUĞU GÖRÜNÜMÜ", "MENU BAR APPEARANCE")) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(MenuBarStyle.allCases) { style in
                        Button(action: {
                            settings.menuBarStyle = style
                        }) {
                            HStack {
                                Image(systemName: settings.menuBarStyle == style ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(settings.menuBarStyle == style ? .accentColor : .secondary)
                                Text(style.title(isTurkish: isTR))
                                    .font(.system(size: 11))
                                Spacer()
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            
            // Section 3: Uyarı Eşikleri
            settingSection(title: settings.t("YÜKSEK KULLANIM UYARILARI", "HIGH USAGE ALERTS")) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $settings.showColoredAlert) {
                        Text(settings.t("Eşik aşıldığında kırmızıyla uyar", "Show in red when a threshold is exceeded"))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .toggleStyle(SwitchToggleStyle())
                    
                    // CPU Slider & Aligned Scale
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(settings.t("CPU Uyarı Eşiği:", "CPU Alert Threshold:"))
                                .font(.system(size: 11))
                            Spacer()
                            Text(isTR ? "%\(Int(settings.cpuAlertThreshold))" : "\(Int(settings.cpuAlertThreshold))%")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(settings.cpuAlertThreshold >= 80 ? .red : (settings.cpuAlertThreshold >= 60 ? .orange : .blue))
                        }
                        
                        AlignedThresholdSlider(
                            value: $settings.cpuAlertThreshold,
                            range: 20...95,
                            step: 5,
                            presets: [30, 50, 70, 80, 90],
                            accentColor: settings.cpuAlertThreshold >= 80 ? .red : (settings.cpuAlertThreshold >= 60 ? .orange : .blue)
                        )
                    }
                    
                    Divider().padding(.vertical, 1)
                    
                    // RAM Slider & Aligned Scale
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(settings.t("RAM Uyarı Eşiği:", "RAM Alert Threshold:"))
                                .font(.system(size: 11))
                            Spacer()
                            Text(isTR ? "%\(Int(settings.ramAlertThreshold))" : "\(Int(settings.ramAlertThreshold))%")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(settings.ramAlertThreshold >= 85 ? .red : (settings.ramAlertThreshold >= 70 ? .orange : .blue))
                        }
                        
                        AlignedThresholdSlider(
                            value: $settings.ramAlertThreshold,
                            range: 20...95,
                            step: 5,
                            presets: [30, 50, 70, 80, 90],
                            accentColor: settings.ramAlertThreshold >= 85 ? .red : (settings.ramAlertThreshold >= 70 ? .orange : .blue)
                        )
                    }
                }
            }
            
            // Section 4: Diğer Seçenekler & Dil
            settingSection(title: settings.t("GENEL SEÇENEKLER VE DİL", "GENERAL OPTIONS & LANGUAGE")) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(settings.t("Uygulama Dili", "Language"), systemImage: "globe")
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Picker("", selection: $settings.appLanguage) {
                            ForEach(AppLanguage.allCases) { lang in
                                Text(lang.title(isTurkish: isTR)).tag(lang)
                            }
                        }
                        .frame(width: 170)
                    }
                    
                    Divider().padding(.vertical, 1)
                    
                    Toggle(isOn: $settings.showSparkline) {
                        Text(settings.t("Mini geçmiş grafiklerini göster", "Show mini history graphs"))
                            .font(.system(size: 11))
                    }
                    .toggleStyle(SwitchToggleStyle())
                    
                    Toggle(isOn: $settings.launchAtLogin) {
                        Text(settings.t("Mac açılışında otomatik başlat", "Launch automatically at login"))
                            .font(.system(size: 11))
                    }
                    .toggleStyle(SwitchToggleStyle())
                    
                    Toggle(isOn: $settings.autoCheckUpdates) {
                        Text(settings.t("Güncellemeleri otomatik denetle", "Check for updates automatically"))
                            .font(.system(size: 11))
                    }
                    .toggleStyle(SwitchToggleStyle())
                    .help(settings.t("Günde bir kez GitLab'daki son sürüme bakar; bu Mac hakkında bilgi göndermez.",
                                     "Looks at the latest release on GitLab once a day; sends nothing about this Mac."))
                }
            }
            
            // Section 5: Çıkış & Hakkında
            VStack(spacing: 8) {
                if isConfirmingQuit {
                    HStack(spacing: 8) {
                        // 2. Koruma (Evet, Çık) EN SOLDA yer alır -> sağdaki ilk "Çıkış" butonundan tamamen uzağa kayar
                        Button(action: {
                            guard canConfirmQuit else { return }
                            NSApplication.shared.terminate(nil)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "power")
                                Text(settings.t("Evet, Çık", "Yes, Quit"))
                                    .lineLimit(1)
                            }
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(canConfirmQuit ? Color.red : Color.red.opacity(0.4))
                            .cornerRadius(6)
                            .fixedSize(horizontal: true, vertical: false)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(!canConfirmQuit)
                        .help(settings.t("MacMonitor uygulamasını kapat", "Quit MacMonitor"))
                        
                        Spacer(minLength: 4)
                        
                        Text(settings.t("Uygulamadan çıkılsın mı?", "Quit MacMonitor?"))
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(.red)
                            .lineLimit(1)
                        
                        Spacer(minLength: 4)
                        
                        // Vazgeç EN SAĞDA yer alır -> ilk "Çıkış" butonunun tam üzerine denk gelir
                        Button(action: {
                            cancelQuitConfirmation()
                        }) {
                            Text(settings.t("Vazgeç", "Cancel"))
                                .lineLimit(1)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.primary.opacity(0.12))
                                .cornerRadius(6)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .frame(height: 32)
                } else {
                    HStack(spacing: 6) {
                        Button(action: {
                            AboutWindowManager.shared.show()
                        }) {
                            HStack(spacing: 7) {
                                AppLogoBadgeView(size: 28, showGlow: false)
                                
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("MacMonitor v\(SystemInfoHelper.appVersion)")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                    Text("Rafet Sapancı • GPL v3.0")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help(settings.t("Hakkında penceresini aç", "Open About window"))
                        
                        Spacer(minLength: 4)
                        
                        Button(action: {
                            AboutWindowManager.shared.show()
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "info.circle")
                                Text(settings.t("Hakkında", "About"))
                                    .lineLimit(1)
                            }
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.08))
                            .cornerRadius(6)
                            .fixedSize(horizontal: true, vertical: false)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help(settings.t("Bağımsız Hakkında penceresini aç", "Open standalone About window"))
                        
                        Button(action: {
                            startQuitConfirmation()
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "power")
                                Text(settings.t("Çıkış", "Quit"))
                                    .lineLimit(1)
                            }
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.85))
                            .cornerRadius(6)
                            .fixedSize(horizontal: true, vertical: false)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .frame(height: 32)
                }
            }
            .padding(10)
            .background(isConfirmingQuit ? Color.red.opacity(0.08) : Color.primary.opacity(0.03))
            .cornerRadius(8)
        }
        .onDisappear {
            cancelQuitConfirmation()
        }
    }
    
    private func startQuitConfirmation() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isConfirmingQuit = true
            canConfirmQuit = false
        }
        quitResetTask?.cancel()
        quitResetTask = Task {
            // 500ms safety lockout against accidental rapid double-clicking
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation {
                    canConfirmQuit = true
                }
            }
            // Auto-revert back to standard button after 6 seconds of inactivity
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation {
                    isConfirmingQuit = false
                    canConfirmQuit = false
                }
            }
        }
    }
    
    private func cancelQuitConfirmation() {
        quitResetTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            isConfirmingQuit = false
            canConfirmQuit = false
        }
    }
    
    private func settingSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.leading, 2)
            
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }
}
