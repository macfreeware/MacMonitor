import SwiftUI
import Charts

/// Charge level with the line colored by state, and below it one strip for the state and one for
/// the display, so charging and screen time can be read at a glance. The strips live in the same
/// chart to stay aligned with the line.
struct BatteryPercentChart: View {
    let model: BatteryChartModel
    @ObservedObject var settings: AppSettings
    @Binding var hoverTime: Date?
    var large = false
    var onZoom: ((Date, Date) -> Void)? = nil

    private var locale: Locale { Locale(identifier: settings.t("tr_TR", "en_US")) }
    private var desired: Int { large ? 10 : 4 }
    private var span: TimeInterval { model.end.timeIntervalSince(model.start) }

    var body: some View {
        Chart {
            RuleMark(y: .value("Low", 20))
                .foregroundStyle(Color.red.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
            ForEach(model.spans) { s in
                RectangleMark(xStart: .value("Start", s.start), xEnd: .value("End", s.end),
                              yStart: .value("Strip", -9), yEnd: .value("Strip", -3))
                    .foregroundStyle(s.state.color)
            }
            ForEach(model.screenSpans) { s in
                RectangleMark(xStart: .value("Start", s.start), xEnd: .value("End", s.end),
                              yStart: .value("Screen", -16), yEnd: .value("Screen", -11))
                    .foregroundStyle(BatteryLegend.screenColor)
            }
            ForEach(model.points) { p in
                AreaMark(x: .value("Time", p.time), yStart: .value("Base", 0), yEnd: .value("%", p.percent),
                         series: .value("Segment", p.segment))
                    .foregroundStyle(LinearGradient(colors: [p.state.color.opacity(0.26), p.state.color.opacity(0.03)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", p.time), y: .value("%", p.percent), series: .value("Segment", p.segment))
                    .foregroundStyle(p.state.color)
                    .lineStyle(StrokeStyle(lineWidth: large ? 2.4 : 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            if let last = model.points.last, hoverTime == nil {
                PointMark(x: .value("Time", last.time), y: .value("%", last.percent))
                    .symbolSize(30)
                    .foregroundStyle(last.state.color)
            }
            if let t = hoverTime, let p = BatteryPercentChart.nearest(model, to: t) {
                RuleMark(x: .value("Time", p.time))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: p.time > model.start.addingTimeInterval(span / 2) ? .leading : .trailing,
                                alignment: .top) {
                        hoverLabel(p)
                    }
                PointMark(x: .value("Time", p.time), y: .value("%", p.percent))
                    .symbolSize(36)
                    .foregroundStyle(p.state.color)
            }
        }
        .chartXScale(domain: model.start...model.end)
        // Headroom above 100% so a full battery's line is not cut; room below 0 for the strips
        .chartYScale(domain: -18...106)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                AxisValueLabel {
                    Text(verbatim: "\(value.as(Int.self) ?? 0)%")
                        .font(.system(size: large ? 10 : 8))
                        .frame(width: large ? 34 : 26, alignment: .trailing)
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: HistoryAxis.ticks(start: model.start, end: model.end, desired: desired)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                if let d = value.as(Date.self), HistoryAxis.hasRoom(d, start: model.start, end: model.end) {
                    AxisValueLabel(format: HistoryAxis.labelFormat(span: span, desired: desired, locale: locale))
                        .font(.system(size: large ? 10 : 8))
                }
            }
        }
        .chartOverlay { proxy in
            ChartPointerOverlay(proxy: proxy, hoverTime: $hoverTime, onZoom: onZoom)
        }
    }

    static func nearest(_ model: BatteryChartModel, to time: Date) -> BatteryChartModel.Point? {
        model.points.min { abs($0.time.timeIntervalSince(time)) < abs($1.time.timeIntervalSince(time)) }
    }

    private func hoverLabel(_ p: BatteryChartModel.Point) -> some View {
        // formatted(), because Text(_:format:) would use the system language, not MacMonitor's
        let time = p.time.formatted(HistoryAxis.timeFormat(locale))
        let day = p.time.formatted(Date.FormatStyle.dateTime.day().month(.abbreviated).locale(locale))
        return VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: span <= 86_400 ? time : "\(day) \(time)")
            Text(verbatim: "\(Int(p.percent.rounded()))%" + (p.watts.map { " · " + BatteryInfo.formatWatts($0) } ?? ""))
                .fontWeight(.semibold)
            Text(p.state.title(settings)).foregroundColor(p.state.color)
            if let on = p.screenOn {
                Text(on ? settings.t("Ekran açık", "Screen on") : settings.t("Ekran kapalı", "Screen off"))
                    .foregroundColor(.secondary)
            }
        }
        .font(.system(size: large ? 11 : 9))
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color(NSColor.windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.15), lineWidth: 0.5))
    }
}

struct BatteryWattsChart: View {
    let model: BatteryChartModel
    @Binding var hoverTime: Date?
    var large = false
    var onZoom: ((Date, Date) -> Void)? = nil

    var body: some View {
        let peak = model.points.compactMap(\.watts).max() ?? 10
        let maxW = max(10, peak * 1.15)
        Chart {
            ForEach(model.points.filter { $0.watts != nil }) { p in
                AreaMark(x: .value("Time", p.time), y: .value("W", p.watts ?? 0), series: .value("Segment", p.segment))
                    .foregroundStyle(LinearGradient(colors: [Color.purple.opacity(0.3), Color.purple.opacity(0.03)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", p.time), y: .value("W", p.watts ?? 0), series: .value("Segment", p.segment))
                    .foregroundStyle(Color.purple)
                    .lineStyle(StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            if let t = hoverTime, let p = BatteryPercentChart.nearest(model, to: t) {
                RuleMark(x: .value("Time", p.time)).foregroundStyle(Color.secondary.opacity(0.6))
            }
        }
        .chartXScale(domain: model.start...model.end)
        .chartYScale(domain: 0...maxW)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, maxW / 1.15]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                AxisValueLabel {
                    Text(verbatim: "\(Int((value.as(Double.self) ?? 0).rounded())) W")
                        .font(.system(size: large ? 10 : 8))
                        .frame(width: large ? 34 : 26, alignment: .trailing)
                }
            }
        }
        .chartOverlay { proxy in
            ChartPointerOverlay(proxy: proxy, hoverTime: $hoverTime, onZoom: onZoom)
        }
    }
}

/// What each color means, with the time spent in it
struct BatteryLegend: View {
    static let screenColor = Color.indigo
    let model: BatteryChartModel
    @ObservedObject var settings: AppSettings
    var fontSize: CGFloat = 9
    /// Two rows for the narrow panel, one row in the detail window
    var compact = true

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: compact ? 2 : 4),
                  alignment: .leading, spacing: 3) {
            item(.charging, model.chargingTime)
            item(.pluggedIn, model.pluggedTime)
            item(.onBattery, model.batteryTime)
            if !model.screenSpans.isEmpty {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(Self.screenColor).frame(width: 10, height: 7)
                    Text(verbatim: settings.t("Ekran açık ", "Screen on ") + Self.duration(model.screenTime, settings))
                }
            }
        }
        .font(.system(size: fontSize))
        .foregroundColor(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func item(_ state: BatteryState, _ time: TimeInterval) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(state.color).frame(width: 10, height: 7)
            Text(verbatim: "\(state.title(settings)) \(BatteryLegend.duration(time, settings))")
        }
    }

    static func duration(_ time: TimeInterval, _ settings: AppSettings) -> String {
        let minutes = Int(time / 60)
        if minutes >= 48 * 60 {
            return settings.t("\(minutes / 1440) gün \(minutes % 1440 / 60) sa", "\(minutes / 1440) d \(minutes % 1440 / 60) h")
        }
        if minutes >= 600 { return settings.t("\(minutes / 60) sa", "\(minutes / 60) h") }
        return BatteryInfo.formatMinutes(minutes, turkish: settings.isTurkish)
    }
}
