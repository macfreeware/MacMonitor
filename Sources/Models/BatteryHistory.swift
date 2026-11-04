import AppKit
import Foundation

public struct BatterySample: Equatable {
    public var time: Date
    public var percent: Int
    public var isOnAC: Bool
    public var isCharging: Bool
    /// Whole-system power in watts, when the Mac reports it
    public var watts: Double?
}

/// Records the battery once a minute, also while the panel is closed, and keeps 90 days
/// on disk (~1 MB) so the Battery tab can draw a much longer history than macOS's 24 hours.
/// Samples live in memory only while the chart is on screen.
@MainActor
public final class BatteryHistory {
    public static let shared = BatteryHistory()

    public static let interval: TimeInterval = 60
    public static let keepDays: Double = 90

    private var timer: Timer?
    private var pending: [BatterySample] = []
    private var observers: [NSObjectProtocol] = []
    private var termSource: DispatchSourceSignal?

    private static let recordSize = 8

    private let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MacMonitor", isDirectory: true)
            .appendingPathComponent("battery-history.bin")
    }()

    private init() {}

    public func start() {
        guard timer == nil, BatteryInfo.isPresent else { return }
        prune()
        record()
        let t = Timer(timeInterval: Self.interval, repeats: true) { _ in
            MainActor.assumeIsolated { BatteryHistory.shared.record() }
        }
        t.tolerance = 15  // let macOS group the wake-ups
        RunLoop.main.add(t, forMode: .common)
        timer = t

        let ws = NSWorkspace.shared.notificationCenter
        observers.append(ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { BatteryHistory.shared.flush() }
        })
        observers.append(ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { BatteryHistory.shared.record() }
        })

        // The installer stops a running copy with SIGTERM, which skips applicationWillTerminate
        signal(SIGTERM, SIG_IGN)
        let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        term.setEventHandler {
            MainActor.assumeIsolated { BatteryHistory.shared.flush() }
            exit(0)
        }
        term.resume()
        termSource = term
    }

    public func record() {
        guard let b = BatteryInfo.read() else { return }
        pending.append(BatterySample(time: Date(), percent: b.percent, isOnAC: b.isOnAC,
                                     isCharging: b.state == .charging, watts: b.systemWatts))
        // Write in batches to spare the disk; sleep and quit flush the rest
        if pending.count >= 10 { flush() }
    }

    public func flush() {
        guard !pending.isEmpty else { return }
        var data = Data(capacity: pending.count * Self.recordSize)
        for s in pending { Self.encode(s, into: &data) }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                try data.write(to: fileURL)
            } else {
                let handle = try FileHandle(forWritingTo: fileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            }
            pending.removeAll()
        } catch {
            // Keep the samples and try again with the next batch
        }
    }

    /// Everything recorded so far, oldest first, including samples not yet written
    public func load() -> [BatterySample] {
        var samples = (try? Data(contentsOf: fileURL)).map(Self.decode) ?? []
        samples.append(contentsOf: pending)
        return samples
    }

    /// Drops samples older than keepDays; runs once at launch
    private func prune() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let all = Self.decode(data)
        let cutoff = Date().addingTimeInterval(-Self.keepDays * 86_400)
        guard let first = all.first, first.time < cutoff else { return }
        var kept = Data()
        for s in all where s.time >= cutoff { Self.encode(s, into: &kept) }
        try? kept.write(to: fileURL, options: .atomic)
    }

    // MARK: - File format: 8 bytes per sample, little endian
    // UInt32 Unix time · UInt8 percent · UInt8 flags (1 on AC, 2 charging, 4 has watts) · UInt16 watts × 10

    private static func encode(_ s: BatterySample, into data: inout Data) {
        var time = UInt32(clamping: Int(s.time.timeIntervalSince1970)).littleEndian
        var flags: UInt8 = 0
        if s.isOnAC { flags |= 1 }
        if s.isCharging { flags |= 2 }
        var watts: UInt16 = 0
        if let w = s.watts {
            flags |= 4
            watts = UInt16(clamping: Int((w * 10).rounded()))
        }
        watts = watts.littleEndian
        withUnsafeBytes(of: &time) { data.append(contentsOf: $0) }
        data.append(UInt8(clamping: s.percent))
        data.append(flags)
        withUnsafeBytes(of: &watts) { data.append(contentsOf: $0) }
    }

    private static func decode(_ data: Data) -> [BatterySample] {
        let count = data.count / recordSize
        var out: [BatterySample] = []
        out.reserveCapacity(count)
        data.withUnsafeBytes { raw in
            for i in 0..<count {
                let o = i * recordSize
                let time = UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: o, as: UInt32.self))
                let percent = Int(raw[o + 4])
                let flags = raw[o + 5]
                let watts = UInt16(littleEndian: raw.loadUnaligned(fromByteOffset: o + 6, as: UInt16.self))
                out.append(BatterySample(time: Date(timeIntervalSince1970: TimeInterval(time)), percent: percent,
                                         isOnAC: flags & 1 != 0, isCharging: flags & 2 != 0,
                                         watts: flags & 4 != 0 ? Double(watts) / 10 : nil))
            }
        }
        return out
    }
}
