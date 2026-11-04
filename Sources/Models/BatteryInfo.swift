import Foundation
import IOKit
import IOKit.ps

public struct BatteryInfo: Equatable {
    public enum State: Equatable {
        case charging, onBattery, fullyCharged, notCharging
    }

    public var percent: Int
    public var state: State
    public var isOnAC: Bool
    /// macOS's estimate in minutes; nil while it is still calculating
    public var minutesToEmpty: Int?
    public var minutesToFull: Int?
    /// Whole-system power in watts (Apple Silicon power telemetry); nil when not reported
    public var systemWatts: Double?
    /// Power into (+) or out of (−) the battery, in watts
    public var batteryWatts: Double?
    public var healthPercent: Int?
    public var cycleCount: Int?
    public var designCycles: Int?
    public var temperatureC: Double?
    public var voltage: Double?
    public var adapterName: String?
    public var adapterWatts: Int?
    /// macOS's own verdict, e.g. "Service Recommended"; nil when normal
    public var serviceCondition: String?

    /// Desktop Macs have no battery; checked once, a battery cannot appear later
    public static let isPresent: Bool = read() != nil

    public static func read() -> BatteryInfo? {
        guard let ps = readPowerSource() else { return nil }
        var info = ps
        readSmartBattery(into: &info)
        return info
    }

    // MARK: - IOKit power sources (the same values as the menu bar battery icon)

    private static func readPowerSource() -> BatteryInfo? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  desc[kIOPSIsPresentKey] as? Bool ?? true else { continue }

            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            let percent = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : current
            let onAC = desc[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let charging = desc[kIOPSIsChargingKey] as? Bool ?? false
            let charged = desc[kIOPSIsChargedKey] as? Bool ?? false

            let state: State
            if !onAC {
                state = .onBattery
            } else if charging {
                state = .charging
            } else if charged || percent >= 100 {
                state = .fullyCharged
            } else {
                state = .notCharging  // e.g. Optimized Battery Charging holding at 80%
            }

            // -1 means macOS is still calculating
            func minutes(_ key: String) -> Int? {
                guard let m = desc[key] as? Int, m >= 0 else { return nil }
                return m
            }
            let condition = desc["BatteryHealthCondition"] as? String

            return BatteryInfo(
                percent: min(100, Swift.max(0, percent)),
                state: state,
                isOnAC: onAC,
                minutesToEmpty: onAC ? nil : minutes(kIOPSTimeToEmptyKey),
                minutesToFull: state == .charging ? minutes(kIOPSTimeToFullChargeKey) : nil,
                systemWatts: nil, batteryWatts: nil, healthPercent: nil, cycleCount: nil,
                designCycles: nil, temperatureC: nil, voltage: nil, adapterName: nil, adapterWatts: nil,
                serviceCondition: (condition?.isEmpty == false) ? condition : nil
            )
        }
        return nil
    }

    // MARK: - Battery controller details (IORegistry AppleSmartBattery, readable without privileges)

    private static func readSmartBattery(into info: inout BatteryInfo) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return }

        // Amperage is a signed value that IOKit may hand over as a wrapped unsigned number
        func int(_ value: Any?) -> Int? {
            guard let n = value as? NSNumber else { return nil }
            return Int(truncatingIfNeeded: n.int64Value)
        }
        let data = dict["BatteryData"] as? [String: Any] ?? [:]

        info.cycleCount = int(dict["CycleCount"])
        info.designCycles = int(dict["DesignCycleCount9C"])

        // Health as System Settings shows "Maximum Capacity": full-charge capacity against design capacity
        let design = int(data["DesignCapacity"]) ?? int(dict["DesignCapacity"])
        let nominal = int(data["NominalChargeCapacity"]) ?? int(dict["NominalChargeCapacity"]) ?? int(dict["AppleRawMaxCapacity"])
        if let d = design, let n = nominal, d > 0 {
            info.healthPercent = min(100, Int((Double(n) / Double(d) * 100).rounded(.up)))
        }

        if let mV = int(dict["Voltage"]), mV > 0 {
            info.voltage = Double(mV) / 1000
            if let mA = int(dict["InstantAmperage"]) ?? int(dict["Amperage"]), mA != 0 {
                info.batteryWatts = Double(mV) * Double(mA) / 1_000_000
            }
        }
        if let telemetry = dict["PowerTelemetryData"] as? [String: Any],
           let load = int(telemetry["SystemLoad"]), load > 0 {
            info.systemWatts = Double(load) / 1000
        }
        // Reported in hundredths of a degree on Macs that expose it
        if let t = int(dict["Temperature"]) ?? int(dict["VirtualTemperature"]), t > 0 {
            info.temperatureC = Double(t) / 100
        }
        if info.isOnAC, let adapter = dict["AdapterDetails"] as? [String: Any] {
            info.adapterWatts = int(adapter["Watts"])
            if let name = adapter["Name"] as? String, !name.isEmpty { info.adapterName = name }
        }
    }

    // MARK: - Formatting

    public static func formatMinutes(_ minutes: Int, turkish: Bool) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return turkish ? "\(m) dk" : "\(m) min" }
        return turkish ? "\(h) sa \(m) dk" : "\(h) h \(m) min"
    }

    public static func formatWatts(_ watts: Double) -> String {
        String(format: "%.1f W", abs(watts))
    }
}
