import SwiftUI
import Charts

/// Traffic added up per minute, hour, day or month
struct NetworkBuckets {
    struct Bar: Identifiable {
        let id: Int
        let time: Date
        let isDown: Bool
        let bytes: Double
    }

    struct Row: Identifiable {
        var id: Date { time }
        let time: Date
        let down: Double
        let up: Double
    }

    var unit: Calendar.Component = .hour
    var starts: [Date] = []
    var bars: [Bar] = []
    var rows: [Row] = []
    var end = Date()

    init() {}

    /// The last `count` units up to now, the current one included
    init(samples: [NetworkSample], unit: Calendar.Component, count: Int) {
        let calendar = Calendar.current
        let current = calendar.dateInterval(of: unit, for: Date())?.start ?? Date()
        let starts = (0..<count).reversed().compactMap { calendar.date(byAdding: unit, value: -$0, to: current) }
        self.init(samples: samples, unit: unit, starts: starts,
                  end: calendar.date(byAdding: unit, value: 1, to: current) ?? current)
    }

    /// Every unit touching the range
    init(samples: [NetworkSample], from: Date, to: Date, unit: Calendar.Component) {
        let calendar = Calendar.current
        var starts: [Date] = []
        var t = calendar.dateInterval(of: unit, for: from)?.start ?? from
        while t < to, let next = calendar.date(byAdding: unit, value: 1, to: t) {
            starts.append(t)
            t = next
        }
        self.init(samples: samples, unit: unit, starts: starts, end: t)
    }

    private init(samples: [NetworkSample], unit: Calendar.Component, starts: [Date], end: Date) {
        self.unit = unit
        self.starts = starts
        self.end = end
        guard let first = starts.first else { return }
        var down = [Double](repeating: 0, count: starts.count)
        var up = down
        var index = 0
        for sample in samples where sample.time >= first && sample.time < end {
            while index + 1 < starts.count && sample.time >= starts[index + 1] { index += 1 }
            down[index] += sample.downBytes
            up[index] += sample.upBytes
        }
        for i in starts.indices where down[i] + up[i] > 0 {
            bars.append(Bar(id: i * 2, time: starts[i], isDown: true, bytes: down[i]))
            bars.append(Bar(id: i * 2 + 1, time: starts[i], isDown: false, bytes: up[i]))
            rows.append(Row(time: starts[i], down: down[i], up: up[i]))
        }
    }

    /// The bucket under the pointer
    func start(at time: Date) -> Date? {
        starts.last { $0 <= time }
    }

    func title(for start: Date, locale: Locale) -> String {
        let time = HistoryAxis.timeFormat(locale)
        switch unit {
        case .minute, .hour:
            return "\(start.formatted(Date.FormatStyle.dateTime.day().month(.abbreviated).locale(locale))) \(start.formatted(time))"
        case .day:
            return start.formatted(Date.FormatStyle.dateTime.day().month(.wide).weekday(.abbreviated).locale(locale))
        default:
            return start.formatted(Date.FormatStyle.dateTime.month(.wide).year().locale(locale))
        }
    }
}

struct NetworkBarChart: View {
    let buckets: NetworkBuckets
    @ObservedObject var settings: AppSettings
    @Binding var hoverTime: Date?
    var large = false
    var onZoom: ((Date, Date) -> Void)? = nil

    private var locale: Locale { Locale(identifier: settings.t("tr_TR", "en_US")) }

    var body: some View {
        let first = buckets.starts.first ?? Date()
        let span = buckets.end.timeIntervalSince(first)
        let desired = large ? 10 : 4
        Chart {
            ForEach(buckets.bars) { bar in
                BarMark(x: .value("Time", bar.time, unit: buckets.unit), y: .value("Bytes", bar.bytes))
                    .foregroundStyle(bar.isDown ? NetworkColors.down : NetworkColors.up)
            }
            if let hover = hoverTime.flatMap(buckets.start(at:)) {
                RectangleMark(x: .value("Time", hover, unit: buckets.unit))
                    .foregroundStyle(Color.primary.opacity(0.08))
            }
        }
        .chartXScale(domain: first...buckets.end)
        .chartXAxis {
            AxisMarks(values: HistoryAxis.ticks(start: first, end: buckets.end, desired: desired)) { value in
                AxisTick()
                if let d = value.as(Date.self), HistoryAxis.hasRoom(d, start: first, end: buckets.end) {
                    AxisValueLabel(format: HistoryAxis.labelFormat(span: span, desired: desired, locale: locale))
                        .font(.system(size: large ? 10 : 8.5))
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: large ? 5 : 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(NetworkInfo.formatBytes(v, turkish: settings.isTurkish))
                            .font(.system(size: large ? 10 : 8.5))
                    }
                }
            }
        }
        .chartOverlay { proxy in
            ChartPointerOverlay(proxy: proxy, hoverTime: $hoverTime, onZoom: onZoom)
        }
    }
}
