import SwiftUI
import AppKit

public struct BatteryView: View {
    @ObservedObject var settings: AppSettings
    @State private var battery: BatteryInfo? = nil

    // Power draw changes quickly, the rest slowly; read only while this tab is visible
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    public init(settings: AppSettings) {
        self.settings = settings
    }

    private var isTR: Bool { settings.t("tr", "en") == "tr" }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let b = battery {
                chargeCard(b)
                BatteryHistoryChart(settings: settings)
                detailsCard(b)
            } else {
                Text(settings.t("Pil bilgisi okunamadı.", "Could not read battery information."))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            }

            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.system(size: 8.5))
                    .foregroundColor(.secondary)
                Text(settings.t("Kalan süre macOS'un tahminidir; fişten çektikten sonra birkaç dakika hesaplanır.",
                                "Time remaining is macOS's estimate; it takes a few minutes after unplugging."))
                    .font(.system(size: 8.5))
                    .foregroundColor(.secondary)
            }
        }
        .onAppear { battery = BatteryInfo.read() }
        .onReceive(timer) { _ in
            let fresh = BatteryInfo.read()
            if fresh != battery { battery = fresh }
        }
    }

    // MARK: - Charge

    private func levelColor(_ b: BatteryInfo) -> Color {
        if b.state == .charging || b.state == .fullyCharged { return .green }
        if b.percent <= 10 { return .red }
        if b.percent <= 20 { return .orange }
        return .green
    }

    private func stateText(_ b: BatteryInfo) -> String {
        switch b.state {
        case .charging: return settings.t("Şarj oluyor", "Charging")
        case .onBattery: return settings.t("Pilde çalışıyor", "On battery")
        case .fullyCharged: return settings.t("Tam dolu", "Fully charged")
        case .notCharging: return settings.t("Şarj beklemede", "Not charging")
        }
    }

    private func stateIcon(_ b: BatteryInfo) -> String {
        switch b.state {
        case .charging: return "battery.100percent.bolt"
        case .fullyCharged, .notCharging: return "powerplug"
        case .onBattery:
            switch b.percent {
            case ..<13: return "battery.0percent"
            case ..<38: return "battery.25percent"
            case ..<63: return "battery.50percent"
            case ..<88: return "battery.75percent"
            default: return "battery.100percent"
            }
        }
    }

    private func timeText(_ b: BatteryInfo) -> String? {
        switch b.state {
        case .onBattery:
            guard let m = b.minutesToEmpty else { return settings.t("Kalan süre hesaplanıyor…", "Calculating time remaining…") }
            return settings.t("Kalan süre: ", "Time remaining: ") + BatteryInfo.formatMinutes(m, turkish: isTR)
        case .charging:
            guard let m = b.minutesToFull else { return settings.t("Dolma süresi hesaplanıyor…", "Calculating time to full…") }
            return settings.t("Dolmasına: ", "Full in: ") + BatteryInfo.formatMinutes(m, turkish: isTR)
        case .notCharging:
            return settings.t("macOS şarjı şimdilik bekletiyor (ör. optimize şarj)", "macOS is holding the charge for now (e.g. optimized charging)")
        case .fullyCharged:
            return nil
        }
    }

    private func chargeCard(_ b: BatteryInfo) -> some View {
        let color = levelColor(b)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(settings.t("Pil", "Battery"), systemImage: stateIcon(b))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                Text(verbatim: "\(b.percent)%")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(color)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: max(0, geo.size.width * CGFloat(b.percent) / 100))
                }
            }
            .frame(height: 8)

            HStack(spacing: 4) {
                Text(stateText(b))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                if b.isOnAC, let name = b.adapterName ?? b.adapterWatts.map({ "\($0) W" }) {
                    Text(verbatim: "· \(name)")
                        .lineLimit(1)
                }
                Spacer()
            }
            .font(.system(size: 10))
            .foregroundColor(.secondary)

            if let time = timeText(b) {
                Text(time)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
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

    // MARK: - Details

    private func healthColor(_ percent: Int) -> Color {
        if percent >= 80 { return .primary }
        if percent >= 70 { return .orange }
        return .red
    }

    private func detailsCard(_ b: BatteryInfo) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if let w = b.systemWatts {
                row(settings.t("Sistem güç tüketimi", "System power"), BatteryInfo.formatWatts(w),
                    tooltip: settings.t("Mac'in o anda toplam çektiği güç (adaptörden ya da pilden).",
                                        "The total power the Mac is drawing right now (from the adapter or the battery)."))
            }
            if let w = b.batteryWatts {
                row(w > 0 ? settings.t("Pile giren güç", "Charging power") : settings.t("Pilden çekilen güç", "Battery drain"),
                    BatteryInfo.formatWatts(w),
                    tooltip: settings.t("Pilin voltajı × akımı.", "Battery voltage × current."))
            }
            if let h = b.healthPercent {
                row(settings.t("Pil sağlığı (maks. kapasite)", "Health (maximum capacity)"), "\(h)%",
                    color: healthColor(h),
                    tooltip: settings.t("Yeni pilin kapasitesine göre bugün tutabildiği şarj; Sistem Ayarları'ndaki \"Maksimum Kapasite\" ile aynı.",
                                        "Charge the battery holds today compared with when it was new; the same as \"Maximum Capacity\" in System Settings."))
            }
            if let c = b.cycleCount {
                let cycles = b.designCycles.map { "\(c) / \($0)" } ?? "\(c)"
                row(settings.t("Şarj döngüsü", "Cycle count"), cycles,
                    tooltip: settings.t("Pilin tasarlandığı döngü sayısı sağdadır.", "The right-hand number is the cycle count the battery is designed for."))
            }
            if let t = b.temperatureC {
                row(settings.t("Sıcaklık", "Temperature"), String(format: "%.1f °C", t))
            }
            if let v = b.voltage {
                row(settings.t("Voltaj", "Voltage"), String(format: "%.2f V", v))
            }
            if let condition = b.serviceCondition {
                row(settings.t("Durum", "Condition"), condition, color: .red)
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

    private func row(_ title: String, _ value: String, color: Color = .primary, tooltip: String? = nil) -> some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(verbatim: value)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
        .font(.system(size: 10.5))
        .help(tooltip ?? "")
    }
}
