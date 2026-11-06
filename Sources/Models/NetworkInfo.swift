import Foundation
import Darwin

/// Live network speed for the menu bar and the Network tab
public struct NetworkInfo: Equatable {
    public var downBytesPerSecond: Double = 0
    public var upBytesPerSecond: Double = 0
    /// Last 60 seconds, for the Network tab's graph
    public var downHistory: [Double] = []
    public var upHistory: [Double] = []

    /// "1,2 MB/s" or "9,6 Mbit/s", in decimal units as Finder and Activity Monitor count
    public static func formatSpeed(_ bytesPerSecond: Double, turkish: Bool, bits: Bool) -> String {
        bits ? format(bytesPerSecond * 8, units: ["Kbit/s", "Mbit/s", "Gbit/s"], turkish: turkish)
             : format(bytesPerSecond, units: ["KB/s", "MB/s", "GB/s"], turkish: turkish)
    }

    /// "36,6 GB"
    public static func formatBytes(_ bytes: Double, turkish: Bool) -> String {
        format(bytes, units: ["KB", "MB", "GB", "TB"], turkish: turkish)
    }

    private static func format(_ bytes: Double, units: [String], turkish: Bool) -> String {
        var value = max(0, bytes) / 1000
        var unit = 0
        while value >= 999.5 && unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        // A fixed three characters or so keeps the menu bar reading steady
        var text = value >= 9.95 || value == 0 ? String(Int(value.rounded())) : String(format: "%.1f", value)
        if turkish { text = text.replacingOccurrences(of: ".", with: ",") }
        return "\(text) \(units[unit])"
    }
}

/// Bytes moved since the last call, from the kernel's 64-bit interface counters. Only `en*`
/// interfaces count: Wi-Fi, Ethernet and USB tethering. VPN tunnels carry traffic that also
/// passes through those, and the loopback is not network traffic.
struct NetworkCounterReader {
    private var previous: [String: (down: UInt64, up: UInt64)] = [:]
    private var isFirstRead = true

    mutating func readDelta() -> (down: UInt64, up: UInt64) {
        let current = Self.readCounters()
        var down: UInt64 = 0, up: UInt64 = 0
        for (name, counters) in current {
            // A new interface starts from its current value; a reset counter counts as zero
            guard let before = previous[name] else { continue }
            down += counters.down >= before.down ? counters.down - before.down : 0
            up += counters.up >= before.up ? counters.up - before.up : 0
        }
        previous = current
        if isFirstRead {
            isFirstRead = false
            return (0, 0)
        }
        return (down, up)
    }

    /// getifaddrs and NET_RT_IFLIST2 both wrap at 4 GB here; the per-interface MIB entry has the
    /// full 64-bit values, the same ones netstat shows
    static func readCounters() -> [String: (down: UInt64, up: UInt64)] {
        guard let list = if_nameindex() else { return [:] }
        defer { if_freenameindex(list) }
        var result: [String: (down: UInt64, up: UInt64)] = [:]
        var entry = list
        while entry.pointee.if_index != 0, let namePointer = entry.pointee.if_name {
            let name = String(cString: namePointer)
            if name.hasPrefix("en") {
                var mib: [Int32] = [CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_IFDATA,
                                    Int32(entry.pointee.if_index), IFDATA_GENERAL]
                var data = ifmibdata()
                var size = MemoryLayout<ifmibdata>.size
                if sysctl(&mib, 6, &data, &size, nil, 0) == 0 {
                    result[name] = (data.ifmd_data.ifi_ibytes, data.ifmd_data.ifi_obytes)
                }
            }
            entry += 1
        }
        return result
    }
}
