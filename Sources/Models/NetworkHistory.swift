import AppKit
import Foundation

public struct NetworkSample: Equatable {
    public var time: Date
    public var downBytes: Double
    public var upBytes: Double
}

/// Adds up the traffic and writes one record a minute while there was any, keeping 400 days on
/// disk (a few MB at most) so the Network tab can compare this month with the last ones.
/// Only what moves while MacMonitor runs is counted.
@MainActor
public final class NetworkHistory {
    public static let shared = NetworkHistory()

    public nonisolated static let interval: TimeInterval = 60
    public static let keepDays: Double = 400

    private var timer: Timer?
    private var pending: [NetworkSample] = []
    private var unrecordedDown: UInt64 = 0
    private var unrecordedUp: UInt64 = 0
    private var observers: [NSObjectProtocol] = []

    private static let recordSize = 12

    private let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MacMonitor", isDirectory: true)
            .appendingPathComponent("network-history.bin")
    }()

    private init() {}

    public func start() {
        guard timer == nil else { return }
        prune()
        let t = Timer(timeInterval: Self.interval, repeats: true) { _ in
            MainActor.assumeIsolated { NetworkHistory.shared.record() }
        }
        t.tolerance = 15  // let macOS group the wake-ups
        RunLoop.main.add(t, forMode: .common)
        timer = t

        let ws = NSWorkspace.shared.notificationCenter
        observers.append(ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                NetworkHistory.shared.record()
                NetworkHistory.shared.flush()
            }
        })
    }

    /// Called with every counter reading
    public func add(down: UInt64, up: UInt64) {
        unrecordedDown += down
        unrecordedUp += up
    }

    public func record() {
        // Whole kilobytes go into the record; the rest stays for the next minute so totals stay exact
        let downKB = unrecordedDown / 1000, upKB = unrecordedUp / 1000
        guard downKB > 0 || upKB > 0 else { return }
        unrecordedDown %= 1000
        unrecordedUp %= 1000
        pending.append(NetworkSample(time: Date(), downBytes: Double(downKB) * 1000, upBytes: Double(upKB) * 1000))
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
    public func load() -> [NetworkSample] {
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

    // MARK: - File format: 12 bytes per sample, little endian
    // UInt32 Unix time · UInt32 kilobytes down · UInt32 kilobytes up (1 KB = 1000 bytes)

    static func encode(_ s: NetworkSample, into data: inout Data) {
        var fields = [UInt32(clamping: Int(s.time.timeIntervalSince1970)),
                      UInt32(clamping: Int(s.downBytes / 1000)),
                      UInt32(clamping: Int(s.upBytes / 1000))].map(\.littleEndian)
        fields.withUnsafeMutableBytes { data.append(contentsOf: $0) }
    }

    static func decode(_ data: Data) -> [NetworkSample] {
        let count = data.count / recordSize
        var out: [NetworkSample] = []
        out.reserveCapacity(count)
        data.withUnsafeBytes { raw in
            for i in 0..<count {
                let o = i * recordSize
                let time = UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: o, as: UInt32.self))
                let down = UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: o + 4, as: UInt32.self))
                let up = UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: o + 8, as: UInt32.self))
                out.append(NetworkSample(time: Date(timeIntervalSince1970: TimeInterval(time)),
                                         downBytes: Double(down) * 1000, upBytes: Double(up) * 1000))
            }
        }
        return out
    }
}
