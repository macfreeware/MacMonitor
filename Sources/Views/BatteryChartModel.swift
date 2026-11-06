import SwiftUI

/// The three things the charge line can be doing; one color each throughout the battery charts
enum BatteryState: Int {
    case onBattery, pluggedIn, charging

    init(_ sample: BatterySample) {
        if sample.isCharging {
            self = .charging
        } else {
            self = sample.isOnAC ? .pluggedIn : .onBattery
        }
    }

    var color: Color {
        switch self {
        case .charging: return .green
        case .pluggedIn: return .blue
        case .onBattery: return .orange
        }
    }

    func title(_ settings: AppSettings) -> String {
        switch self {
        case .charging: return settings.t("Şarj oluyor", "Charging")
        case .pluggedIn: return settings.t("Prizde", "Plugged in")
        case .onBattery: return settings.t("Pilde", "On battery")
        }
    }
}

/// The samples of one range, reduced to what the charts and summaries draw
struct BatteryChartModel {
    struct Point: Identifiable {
        let id: Int
        let time: Date
        let percent: Double
        let watts: Double?
        let segment: Int
        let state: BatteryState
        let screenOn: Bool?
    }

    struct Span: Identifiable {
        let id: Int
        let start: Date
        let end: Date
        let state: BatteryState
    }

    struct Session: Identifiable {
        let id: Int
        let start: Date
        let end: Date
        let fromPercent: Int
        let toPercent: Int
    }

    var points: [Point] = []
    var spans: [Span] = []
    var sessions: [Session] = []
    /// When the display was on
    var screenSpans: [Span] = []
    var start = Date()
    var end = Date()
    var minPercent: Int?
    var maxPercent: Int?
    var batteryTime: TimeInterval = 0
    var chargingTime: TimeInterval = 0
    var pluggedTime: TimeInterval = 0
    var screenTime: TimeInterval = 0
    var screenOnBatteryTime: TimeInterval = 0
    var avgDrainWatts: Double?

    /// A gap longer than this (sleep, MacMonitor not running) ends a state span
    private static let spanGap: TimeInterval = 5 * 60

    init() {}

    init(samples: [BatterySample], from: Date, to: Date, maxPoints: Int) {
        start = from
        end = to
        let inRange = samples.filter { $0.time >= from && $0.time <= to }
        guard !inRange.isEmpty else { return }
        buildPoints(inRange, maxPoints: maxPoints)
        buildSpansAndStats(inRange)
    }

    /// Averages the samples of each bucket; the line breaks at gaps and changes color with the state
    private mutating func buildPoints(_ samples: [BatterySample], maxPoints: Int) {
        let bucket = max(BatteryHistory.interval, end.timeIntervalSince(start) / Double(maxPoints))
        let gap = max(Self.spanGap, bucket * 2.5)
        var segment = 0
        var lastTime: Date? = nil
        var bucketStart: Date? = nil
        var acc: [BatterySample] = []
        var result: [Point] = []

        func emit() {
            guard let t = bucketStart, !acc.isEmpty else { return }
            let pct = Double(acc.map(\.percent).reduce(0, +)) / Double(acc.count)
            let ws = acc.compactMap(\.watts)
            let w = ws.isEmpty ? nil : ws.reduce(0, +) / Double(ws.count)
            let counts = Dictionary(grouping: acc, by: BatteryState.init).mapValues(\.count)
            let state = counts.max { $0.value < $1.value }?.key ?? .onBattery
            let screens = acc.compactMap(\.screenOn)
            let screenOn = screens.isEmpty ? nil : screens.filter { $0 }.count * 2 >= screens.count
            if let previous = result.last, previous.segment == segment, previous.state != state {
                // Repeat the last point so the new color starts where the old one ended
                segment += 1
                result.append(Point(id: result.count, time: previous.time, percent: previous.percent,
                                    watts: previous.watts, segment: segment, state: state, screenOn: screenOn))
            }
            result.append(Point(id: result.count, time: t.addingTimeInterval(bucket > BatteryHistory.interval ? bucket / 2 : 0),
                                percent: pct, watts: w, segment: segment, state: state, screenOn: screenOn))
            acc.removeAll()
        }

        for s in samples {
            if let last = lastTime, s.time.timeIntervalSince(last) > gap {
                emit()
                segment += 1
                bucketStart = nil
            }
            if let b = bucketStart, s.time.timeIntervalSince(b) >= bucket {
                emit()
                bucketStart = nil
            }
            if bucketStart == nil { bucketStart = s.time }
            acc.append(s)
            lastTime = s.time
        }
        emit()
        points = result
    }

    private mutating func buildSpansAndStats(_ samples: [BatterySample]) {
        var current: (start: Date, state: BatteryState, fromPercent: Int)? = nil
        var last: BatterySample? = nil
        var drainWattSum = 0.0, drainWattCount = 0
        var screenStart: Date? = nil

        func closeScreenSpan(into model: inout BatteryChartModel) {
            guard let start = screenStart, let l = last else { return }
            model.screenSpans.append(Span(id: model.screenSpans.count, start: start,
                                          end: max(l.time, start.addingTimeInterval(BatteryHistory.interval)), state: .onBattery))
            screenStart = nil
        }

        func closeSpan(into model: inout BatteryChartModel) {
            guard let c = current, let l = last else { return }
            // A single reading still gets a visible sliver on the strip
            let spanEnd = max(l.time, c.start.addingTimeInterval(BatteryHistory.interval))
            model.spans.append(Span(id: model.spans.count, start: c.start, end: spanEnd, state: c.state))
            // Brief flickers at the adapter are not charging sessions
            if c.state == .charging, l.time.timeIntervalSince(c.start) >= 2 * 60 {
                model.sessions.append(Session(id: model.sessions.count, start: c.start, end: l.time,
                                              fromPercent: c.fromPercent, toPercent: l.percent))
            }
            current = nil
        }

        for s in samples {
            let state = BatteryState(s)
            let broken = last.map { s.time.timeIntervalSince($0.time) > Self.spanGap } ?? false
            if current != nil, broken || current?.state != state { closeSpan(into: &self) }
            if current == nil { current = (s.time, state, s.percent) }
            if screenStart != nil, broken || s.screenOn != true { closeScreenSpan(into: &self) }
            if screenStart == nil, s.screenOn == true { screenStart = s.time }

            if let l = last, !broken {
                let elapsed = s.time.timeIntervalSince(l.time)
                switch state {
                case .onBattery: batteryTime += elapsed
                case .charging: chargingTime += elapsed
                case .pluggedIn: pluggedTime += elapsed
                }
                if s.screenOn == true {
                    screenTime += elapsed
                    if state == .onBattery { screenOnBatteryTime += elapsed }
                }
            }
            if state == .onBattery, let w = s.watts {
                drainWattSum += w
                drainWattCount += 1
            }
            minPercent = min(minPercent ?? s.percent, s.percent)
            maxPercent = max(maxPercent ?? s.percent, s.percent)
            last = s
        }
        closeSpan(into: &self)
        closeScreenSpan(into: &self)
        if drainWattCount > 0 { avgDrainWatts = drainWattSum / Double(drainWattCount) }
    }
}
