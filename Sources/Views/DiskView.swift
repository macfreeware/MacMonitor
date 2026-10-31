import SwiftUI
import AppKit

public struct DiskView: View {
    @ObservedObject var settings: AppSettings
    @State private var disks: [DiskInfo] = []

    // Disk space changes slowly; read it only while this tab is visible
    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    public init(settings: AppSettings) {
        self.settings = settings
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if disks.isEmpty {
                Text(settings.t("Disk bilgisi okunamadı.", "Could not read disk information."))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(disks) { disk in
                    diskCard(disk)
                }
            }

            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.system(size: 8.5))
                    .foregroundColor(.secondary)
                Text(settings.t("Boş alan, Finder gibi silinebilir (purgeable) alanı da içerir.", "Free space includes purgeable space, as in Finder."))
                    .font(.system(size: 8.5))
                    .foregroundColor(.secondary)
            }
        }
        .onAppear { disks = DiskInfo.readVolumes() }
        .onReceive(timer) { _ in
            let fresh = DiskInfo.readVolumes()
            if fresh != disks { disks = fresh }
        }
    }

    private func statusColor(_ disk: DiskInfo) -> Color {
        if disk.usedPercentage >= 90.0 { return .red }
        if disk.usedPercentage >= 75.0 { return .orange }
        return .green
    }

    private func icon(_ disk: DiskInfo) -> String {
        if disk.isInternal { return "internaldrive" }
        if disk.isRemovable { return "externaldrive.badge.minus" }
        return "externaldrive"
    }

    private func diskCard(_ disk: DiskInfo) -> some View {
        let color = statusColor(disk)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(disk.name, systemImage: icon(disk))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()

                Text(settings.t("\(disk.formattedFree) boş", "\(disk.formattedFree) free"))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(color)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: max(0, geo.size.width * CGFloat(disk.usedPercentage / 100.0)))
                }
            }
            .frame(height: 8)

            HStack {
                Text(settings.t("Kullanılan: \(disk.formattedUsed)", "Used: \(disk.formattedUsed)"))
                Spacer()
                Text(settings.t("Toplam: \(disk.formattedTotal)", "Total: \(disk.formattedTotal)"))
                Text(String(format: "%.0f%%", disk.usedPercentage))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
            .font(.system(size: 10))
            .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            NSWorkspace.shared.open(URL(fileURLWithPath: disk.path))
        }
        .help(settings.t("Finder'da açmak için çift tıklayın", "Double-click to open in Finder"))
    }
}
