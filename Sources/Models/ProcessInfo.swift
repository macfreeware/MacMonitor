import Foundation
import Darwin

public struct ProcessItem: Identifiable, Equatable {
    public var id: pid_t { pid }
    public let pid: pid_t
    public let name: String
    public let cpuPercent: Double
    public let memBytes: UInt64
    
    public var cpuFormatted: String {
        return String(format: "%.1f%%", cpuPercent)
    }
    
    public var memFormatted: String {
        let mb = Double(memBytes) / (1024.0 * 1024.0)
        if mb >= 1024.0 {
            return String(format: "%.1f GB", mb / 1024.0)
        } else {
            return String(format: "%.0f MB", mb)
        }
    }
}
