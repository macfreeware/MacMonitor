import SwiftUI
import Charts

public struct BatteryHistoryChart: View {
    @ObservedObject var settings: AppSettings

    enum Range: Int, CaseIterable {
        // Raw values are stored in the settings, so new ranges get new numbers
        case day = 0, week = 1, month = 2, all = 3, hour = 4
        var seconds: TimeInterval? {
            switch self {
            case .hour: return 3_600
            case .day: return 86_400
            case .week: return 7 * 86_400
            case .month: return 30 * 86_400
            case .all: return nil
            }
        }
    }

    private struct Point: Identifiable {
        let id: Int
        let time: Date
        let percent: Double
        let watts: Double?
        let segment: Int
    }

    private struct Span: Identifiable {
        let id: Int
        let start: Date
        let end: Date
    }

    @AppStorage("batteryHistoryRange") private var rangeRaw: Int = Range.day.rawValue
    @State private var samples: [BatterySample] = []
    @State private var hoverTime: Date? = nil

    // New samples arrive once a minute; refresh the chart at the same pace while it is visible
    private let timer = Timer.publish(every: BatteryHistory.interval, on: .main, in: .common).autoconnect()

    public init(settings: AppSettings) {
        self.settings = settings
    }

    private var range: Range { Range(rawValue: rangeRaw) ?? .day }

    public var body: some View {
        let model = prepare()
        VStack(alignment: .leading, spacing: 8) {
            // Five ranges do not fit next to the title, so the picker gets its own row
            Text(settings.t("Pil geçmişi", "Battery history"))
                .font(.system(size: 11, weight: .semibold))
            HStack {
                Picker("", selection: $rangeRaw) {
                    Text(settings.t("1 sa", "1 h")).tag(Range.hour.rawValue)
                    Text(settings.t("24 sa", "24 h")).tag(Range.day.rawValue)
                    Text(settings.t("7 gün", "7 d")).tag(Range.week.rawValue)
                    Text(settings.t("30 gün", "30 d")).tag(Range.month.rawValue)
                    Text(settings.t("Tümü", "All")).tag(Range.all.rawValue)
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .labelsHidden()
            }

            if model.points.count < 2 {
                Text(settings.t("Geçmiş birikiyor: MacMonitor pili dakikada bir kaydeder.",
                                "History is building up: MacMonitor records the battery once a minute."))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                percentChart(model)
                    .frame(height: 120)
                if model.points.contains(where: { $0.watts != nil }) {
                    wattsChart(model)
                        .frame(height: 54)
                }
                summary(model)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .onAppear { samples = BatteryHistory.shared.load() }
        .onDisappear { samples = [] }  // keep the full history out of memory while hidden
        .onReceive(timer) { _ in samples = BatteryHistory.shared.load() }
    }

    // MARK: - Data

    private struct Model {
        var points: [Point] = []
        var charging: [Span] = []
        var start = Date()
        var end = Date()
        var minPercent: Int?
        var batteryTime: TimeInterval = 0
        var avgDrainWatts: Double?
    }

    private func prepare() -> Model {
        var m = Model()
        let now = Date()
        let from = range.seconds.map { now.addingTimeInterval(-$0) } ?? samples.first?.time ?? now
        let inRange = samples.filter { $0.time >= from }
        guard !inRange.isEmpty else { return m }
        m.start = from
        m.end = now

        // At most ~360 points: average the samples that fall in each bucket
        let bucket = max(BatteryHistory.interval, now.timeIntervalSince(from) / 360)
        // A gap longer than this (sleep, MacMonitor not running) breaks the line
        let gap = max(5 * 60, bucket * 2.5)

        var segment = 0
        var lastTime: Date? = nil
        var bucketStart: Date? = nil
        var acc: [BatterySample] = []

        func emit() {
            guard let t = bucketStart, !acc.isEmpty else { return }
            let pct = Double(acc.map(\.percent).reduce(0, +)) / Double(acc.count)
            let ws = acc.compactMap(\.watts)
            let w = ws.isEmpty ? nil : ws.reduce(0, +) / Double(ws.count)
            m.points.append(Point(id: m.points.count, time: t.addingTimeInterval(bucket > BatteryHistory.interval ? bucket / 2 : 0),
                                  percent: pct, watts: w, segment: segment))
            acc.removeAll()
        }

        var chargeStart: Date? = nil
        var drainWattSum = 0.0, drainWattCount = 0
        for s in inRange {
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

            // Charging periods, drawn as a band behind the line
            if s.isCharging, chargeStart == nil { chargeStart = s.time }
            let chargeBroken = lastTime.map { s.time.timeIntervalSince($0) > gap } ?? false
            if let c = chargeStart, !s.isCharging || chargeBroken {
                m.charging.append(Span(id: m.charging.count, start: c, end: lastTime ?? s.time))
                chargeStart = s.isCharging ? s.time : nil
            }

            if !s.isOnAC {
                if let last = lastTime { m.batteryTime += min(s.time.timeIntervalSince(last), 2 * BatteryHistory.interval) }
                if let w = s.watts { drainWattSum += w; drainWattCount += 1 }
            }
            m.minPercent = min(m.minPercent ?? s.percent, s.percent)
            lastTime = s.time
        }
        emit()
        if let c = chargeStart, let last = lastTime { m.charging.append(Span(id: m.charging.count, start: c, end: last)) }
        if drainWattCount > 0 { m.avgDrainWatts = drainWattSum / Double(drainWattCount) }
        return m
    }

    // MARK: - Charts

    /// Day and month names follow MacMonitor's language, not the system's
    private var locale: Locale { Locale(identifier: settings.t("tr_TR", "en_US")) }

    private var axisFormat: Date.FormatStyle {
        switch range {
        case .hour, .day: return Date.FormatStyle.dateTime.hour().minute().locale(locale)
        case .week: return Date.FormatStyle.dateTime.weekday(.abbreviated).locale(locale)
        case .month, .all: return Date.FormatStyle.dateTime.day().month(.abbreviated).locale(locale)
        }
    }

    /// On the clock's quarter hours (:00, :15, :30, :45), not counted from the window's start
    private func quarterHours(_ model: Model) -> [Date] {
        let quarter: TimeInterval = 15 * 60
        var t = (model.start.timeIntervalSinceReferenceDate / quarter).rounded(.up) * quarter
        var dates: [Date] = []
        while t <= model.end.timeIntervalSinceReferenceDate {
            dates.append(Date(timeIntervalSinceReferenceDate: t))
            t += quarter
        }
        return dates
    }

    private var axisValues: AxisMarkValues {
        switch range {
        case .hour: return .stride(by: .minute, count: 15)
        case .day: return .stride(by: .hour, count: 6)
        case .week: return .stride(by: .day)
        case .month: return .stride(by: .day, count: 7)
        case .all: return .automatic(desiredCount: 5)
        }
    }

    private var hoverFormat: Date.FormatStyle {
        (range == .day || range == .hour ? Date.FormatStyle.dateTime.hour().minute()
                       : Date.FormatStyle.dateTime.day().month(.abbreviated).hour().minute()).locale(locale)
    }

    private func nearest(_ model: Model, to time: Date) -> Point? {
        model.points.min { abs($0.time.timeIntervalSince(time)) < abs($1.time.timeIntervalSince(time)) }
    }

    private func percentChart(_ model: Model) -> some View {
        Chart {
            ForEach(model.charging) { span in
                RectangleMark(xStart: .value("Start", span.start), xEnd: .value("End", span.end),
                              yStart: .value("Min", 0), yEnd: .value("Max", 100))
                    .foregroundStyle(Color.green.opacity(0.10))
            }
            // Low battery guide
            RuleMark(y: .value("Low", 20))
                .foregroundStyle(Color.red.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
            ForEach(model.points) { p in
                AreaMark(x: .value("Time", p.time), y: .value("%", p.percent), series: .value("Segment", p.segment))
                    .foregroundStyle(LinearGradient(colors: [Color.green.opacity(0.32), Color.green.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", p.time), y: .value("%", p.percent), series: .value("Segment", p.segment))
                    .foregroundStyle(Color.green)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            if let last = model.points.last, hoverTime == nil {
                PointMark(x: .value("Time", last.time), y: .value("%", last.percent))
                    .symbolSize(30)
                    .foregroundStyle(Color.green)
            }
            if let t = hoverTime, let p = nearest(model, to: t) {
                RuleMark(x: .value("Time", p.time))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: p.time > model.start.addingTimeInterval(model.end.timeIntervalSince(model.start) / 2) ? .leading : .trailing,
                                alignment: .top) {
                        hoverLabel(p)
                    }
                PointMark(x: .value("Time", p.time), y: .value("%", p.percent))
                    .symbolSize(36)
                    .foregroundStyle(Color.green)
            }
        }
        .chartXScale(domain: model.start...model.end)
        // Headroom above 100% so a full battery's line is not cut by the plot edge
        .chartYScale(domain: 0...106)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                AxisValueLabel { Text(verbatim: "\(value.as(Int.self) ?? 0)%").font(.system(size: 8)) }
            }
        }
        .chartXAxis {
            if range == .hour {
                AxisMarks(values: quarterHours(model)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    // A label right at the edge would be cut off
                    if let d = value.as(Date.self), model.end.timeIntervalSince(d) > model.end.timeIntervalSince(model.start) * 0.1 {
                        AxisValueLabel(format: axisFormat).font(.system(size: 8))
                    }
                }
            } else {
                AxisMarks(values: axisValues) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    // A label right at the edge would be cut off
                    if let d = value.as(Date.self), model.end.timeIntervalSince(d) > model.end.timeIntervalSince(model.start) * 0.1 {
                        AxisValueLabel(format: axisFormat).font(.system(size: 8))
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(Color.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            let x = location.x - geo[proxy.plotAreaFrame].origin.x
                            hoverTime = proxy.value(atX: x, as: Date.self)
                        case .ended:
                            hoverTime = nil
                        }
                    }
            }
        }
    }

    private func wattsChart(_ model: Model) -> some View {
        let maxW = max(10, (model.points.compactMap(\.watts).max() ?? 10) * 1.15)
        return Chart {
            ForEach(model.points.filter { $0.watts != nil }) { p in
                AreaMark(x: .value("Time", p.time), y: .value("W", p.watts ?? 0), series: .value("Segment", p.segment))
                    .foregroundStyle(LinearGradient(colors: [Color.orange.opacity(0.35), Color.orange.opacity(0.03)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", p.time), y: .value("W", p.watts ?? 0), series: .value("Segment", p.segment))
                    .foregroundStyle(Color.orange)
                    .lineStyle(StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            if let t = hoverTime, let p = nearest(model, to: t) {
                RuleMark(x: .value("Time", p.time)).foregroundStyle(Color.secondary.opacity(0.6))
            }
        }
        .chartXScale(domain: model.start...model.end)
        .chartYScale(domain: 0...maxW)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, maxW / 1.15]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                AxisValueLabel { Text(verbatim: "\(Int((value.as(Double.self) ?? 0).rounded())) W").font(.system(size: 8)) }
            }
        }
    }

    private func hoverLabel(_ p: Point) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(p.time, format: hoverFormat)
            Text(verbatim: "\(Int(p.percent.rounded()))%" + (p.watts.map { " · " + BatteryInfo.formatWatts($0) } ?? ""))
                .fontWeight(.semibold)
        }
        .font(.system(size: 9))
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color(NSColor.windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.15), lineWidth: 0.5))
    }

    // MARK: - Summary

    private func summary(_ model: Model) -> some View {
        let isTR = settings.t("tr", "en") == "tr"
        var parts: [String] = []
        if model.batteryTime >= 60 {
            let minutes = Int(model.batteryTime / 60)
            let time = minutes >= 600 ? settings.t("\(minutes / 60) sa", "\(minutes / 60) h") : BatteryInfo.formatMinutes(minutes, turkish: isTR)
            parts.append(settings.t("Pilde ", "On battery ") + time)
        }
        if let low = model.minPercent {
            parts.append(settings.t("en düşük ", "lowest ") + "\(low)%")
        }
        if let w = model.avgDrainWatts {
            parts.append(settings.t("ort. ", "avg. ") + BatteryInfo.formatWatts(w))
        }
        return HStack(spacing: 8) {
            Text(verbatim: parts.joined(separator: " · "))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            HStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 2).fill(Color.green.opacity(0.25)).frame(width: 9, height: 7)
                Text(settings.t("şarj", "charging"))
            }
        }
        .font(.system(size: 9))
        .foregroundColor(.secondary)
    }
}
