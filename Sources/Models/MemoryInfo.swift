import Foundation

public struct MemoryInfo: Equatable {
    public var totalBytes: UInt64 = 0
    public var usedBytes: UInt64 = 0
    public var activeBytes: UInt64 = 0
    public var wiredBytes: UInt64 = 0
    public var compressedBytes: UInt64 = 0
    public var inactiveBytes: UInt64 = 0
    public var freeBytes: UInt64 = 0
    public var swapUsedBytes: UInt64 = 0
    public var swapTotalBytes: UInt64 = 0
    public var history: [Double] = Array(repeating: 0.0, count: 30)
    
    public init() {}
    
    public var usedPercentage: Double {
        guard totalBytes > 0 else { return 0.0 }
        return min(100.0, max(0.0, (Double(usedBytes) / Double(totalBytes)) * 100.0))
    }
    
    public var formattedPercentage: String {
        return String(format: "%.1f%%", usedPercentage)
    }
    
    public var formattedUsed: String {
        return SystemInfoHelper.formatGB(usedBytes)
    }
    
    public var formattedTotal: String {
        return SystemInfoHelper.formatGB(totalBytes)
    }
    
    public var formattedActive: String {
        return SystemInfoHelper.formatGB(activeBytes)
    }
    
    public var formattedWired: String {
        return SystemInfoHelper.formatGB(wiredBytes)
    }
    
    public var formattedCompressed: String {
        return SystemInfoHelper.formatGB(compressedBytes)
    }
    
    public var formattedFree: String {
        return SystemInfoHelper.formatGB(freeBytes + inactiveBytes)
    }
    
    public var formattedSwap: String {
        if swapTotalBytes == 0 {
            return AppSettings.shared.t("Kullanılmıyor", "Not in use")
        }
        return "\(SystemInfoHelper.formatBytes(swapUsedBytes)) / \(SystemInfoHelper.formatBytes(swapTotalBytes))"
    }
}
