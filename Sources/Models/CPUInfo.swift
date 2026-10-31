import Foundation

public struct CPUInfo: Equatable {
    public var totalUsage: Double = 0.0
    public var userUsage: Double = 0.0
    public var systemUsage: Double = 0.0
    public var idleUsage: Double = 100.0
    public var coreUsages: [Double] = []
    public var history: [Double] = Array(repeating: 0.0, count: 30)
    
    public init() {}
    
    public var formattedTotal: String {
        return String(format: "%.1f%%", totalUsage)
    }
    
    public var formattedUser: String {
        return String(format: "%.1f%%", userUsage)
    }
    
    public var formattedSystem: String {
        return String(format: "%.1f%%", systemUsage)
    }
    
    public var formattedIdle: String {
        return String(format: "%.1f%%", idleUsage)
    }
}
