import Foundation

public struct DiskInfo: Identifiable, Equatable {
    public var id: String { path }
    public var name: String
    public var path: String
    public var totalBytes: UInt64
    public var freeBytes: UInt64
    public var isInternal: Bool
    public var isRemovable: Bool

    public var usedBytes: UInt64 { totalBytes > freeBytes ? totalBytes - freeBytes : 0 }

    public var usedPercentage: Double {
        guard totalBytes > 0 else { return 0.0 }
        return min(100.0, max(0.0, Double(usedBytes) / Double(totalBytes) * 100.0))
    }

    public var formattedFree: String { DiskInfo.format(freeBytes) }
    public var formattedUsed: String { DiskInfo.format(usedBytes) }
    public var formattedTotal: String { DiskInfo.format(totalBytes) }

    /// Decimal units, the same way Finder and Disk Utility report disk sizes
    public static func format(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_000_000_000.0
        if gb >= 1000.0 {
            return String(format: "%.2f TB", gb / 1000.0)
        } else if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        }
        return String(format: "%.0f MB", Double(bytes) / 1_000_000.0)
    }

    private static let resourceKeys: [URLResourceKey] = [
        .volumeLocalizedNameKey,
        .volumeTotalCapacityKey,
        .volumeAvailableCapacityKey,
        .volumeAvailableCapacityForImportantUsageKey,
        .volumeIsInternalKey,
        .volumeIsRemovableKey,
        .volumeIsBrowsableKey,
    ]

    /// Mounted volumes the user sees in Finder; the startup disk comes first
    public static func readVolumes() -> [DiskInfo] {
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: resourceKeys,
            options: [.skipHiddenVolumes]
        ) ?? []

        var disks: [DiskInfo] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(resourceKeys)),
                  values.volumeIsBrowsable ?? true,
                  let total = values.volumeTotalCapacity, total > 0 else { continue }
            // "Important usage" includes purgeable space, which is what Finder shows as available
            let important = values.volumeAvailableCapacityForImportantUsage ?? 0
            let plain = Int64(values.volumeAvailableCapacity ?? 0)
            let free = max(important, plain)
            disks.append(DiskInfo(
                name: values.volumeLocalizedName ?? url.lastPathComponent,
                path: url.path,
                totalBytes: UInt64(total),
                freeBytes: UInt64(max(0, free)),
                isInternal: values.volumeIsInternal ?? false,
                isRemovable: values.volumeIsRemovable ?? false
            ))
        }
        return disks.sorted { a, b in
            if (a.path == "/") != (b.path == "/") { return a.path == "/" }
            if a.isInternal != b.isInternal { return a.isInternal }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}
