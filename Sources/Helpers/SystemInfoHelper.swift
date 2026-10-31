import Foundation
import Darwin

public enum SystemInfoHelper {
    
    /// Returns the CPU brand string (e.g. "Apple M2", "Intel Core i7")
    public static var cpuBrand: String = {
        var size: Int = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return "Apple Silicon" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        let brand = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
        return brand.isEmpty ? "Apple Silicon" : brand
    }()
    
    /// Total physical RAM in bytes
    public static var totalPhysicalMemory: UInt64 = {
        var memSize: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        if sysctlbyname("hw.memsize", &memSize, &size, nil, 0) == 0 {
            return memSize
        }
        return ProcessInfo.processInfo.physicalMemory
    }()
    
    /// Number of logical CPU cores
    public static var coreCount: Int = {
        var ncpu: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.ncpu", &ncpu, &size, nil, 0) == 0 && ncpu > 0 {
            return Int(ncpu)
        }
        return ProcessInfo.processInfo.activeProcessorCount
    }()
    
    /// Efficiency cores count on Apple Silicon
    public static var efficiencyCoreCount: Int = {
        var val: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.perflevel1.logicalcpu", &val, &size, nil, 0) == 0 && val > 0 {
            return Int(val)
        }
        return 0
    }()
    
    /// Performance cores count on Apple Silicon
    public static var performanceCoreCount: Int = {
        var val: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.perflevel0.logicalcpu", &val, &size, nil, 0) == 0 && val > 0 {
            return Int(val)
        }
        return coreCount
    }()
    
    /// Formatted system uptime (e.g. "2 gün 4 saat" or "2d 4h")
    public static var formattedUptime: String {
        let isTR = AppSettings.shared.isTurkish
        let uptimeSeconds = ProcessInfo.processInfo.systemUptime
        let days = Int(uptimeSeconds / 86400)
        let hours = Int((uptimeSeconds.truncatingRemainder(dividingBy: 86400)) / 3600)
        let minutes = Int((uptimeSeconds.truncatingRemainder(dividingBy: 3600)) / 60)
        
        if days > 0 {
            return isTR ? "\(days) gün \(hours) saat" : "\(days)d \(hours)h"
        } else if hours > 0 {
            return isTR ? "\(hours) sa \(minutes) dk" : "\(hours)h \(minutes)m"
        } else {
            return isTR ? "\(minutes) dk" : "\(minutes)m"
        }
    }
    
    /// Formats bytes into a human-readable string (e.g. "6.4 GB", "512 MB")
    public static func formatBytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824.0
        if gb >= 1.0 {
            return String(format: "%.2f GB", gb)
        } else {
            let mb = Double(bytes) / 1_048_576.0
            return String(format: "%.0f MB", mb)
        }
    }
    
    /// Formats gigabytes with one decimal place
    public static func formatGB(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824.0
        return String(format: "%.1f GB", gb)
    }
}
