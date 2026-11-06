import SwiftUI

/// Usage report: totals for the usual periods, then a bar chart per minute, hour, day or month
public struct NetworkHistoryView: View {
    @ObservedObject var settings: AppSettings

    enum Range: Int, CaseIterable {
        case hour = 0, day = 1, week = 2, month = 3, year = 4

        var unit: Calendar.Component {
            switch self {
            case .hour: return .minute
            case .day: return .hour
            case .week, .month: return .day
            case .year: return .month
            }
        }
        var bucketCount: Int {
            switch self {
            case .hour: return 60
            case .day: return 24
            case .week: return 7
            case .month: return 30
            case .year: return 12
            }
        }
    }

    private struct Total: Identifiable {
        var id: String { title }
        let title: String
        var down: Double = 0
        var up: Double = 0
    }

    @AppStorage("networkHistoryRange") private var rangeRaw: Int = Range.day.rawValue
    @State private var totals: [Total] = []
    @State private var buckets = NetworkBuckets()
    @State private var hoverTime: Date? = nil

    // New records arrive once a minute; refresh at the same pace while this is visible
    private let timer = Timer.publish(every: NetworkHistory.interval, on: .main, in: .common).autoconnect()

    public init(settings: AppSettings) {
        self.settings = settings
    }

    private var range: Range { Range(rawValue: rangeRaw) ?? .day }
    private var locale: Locale { Locale(identifier: settings.t("tr_TR", "en_US")) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            totalsTable
            Divider()
            HStack {
                Text(settings.t("Geçmiş", "History"))
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                HistoryExpandButton(settings: settings, kind: .network)
            }
            Picker("", selection: $rangeRaw) {
                Text(settings.t("1 sa", "1 h")).tag(Range.hour.rawValue)
                Text(settings.t("24 sa", "24 h")).tag(Range.day.rawValue)
                Text(settings.t("7 gün", "7 d")).tag(Range.week.rawValue)
                Text(settings.t("30 gün", "30 d")).tag(Range.month.rawValue)
                Text(settings.t("12 ay", "12 mo")).tag(Range.year.rawValue)
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .labelsHidden()
            .frame(maxWidth: .infinity)

            if buckets.bars.isEmpty {
                Text(settings.t("Geçmiş birikiyor: MacMonitor trafiği dakikada bir kaydeder.",
                                "History is building up: MacMonitor records the traffic once a minute."))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 104, alignment: .center)
            } else {
                NetworkBarChart(buckets: buckets, settings: settings, hoverTime: $hoverTime)
                    .frame(height: 104)
                summary
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        .onAppear(perform: reload)
        .onChange(of: rangeRaw) { _ in reload() }
        .onChange(of: settings.isTurkish) { _ in reload() }
        .onReceive(timer) { _ in reload() }
    }

    // MARK: - Totals

    private var totalsTable: some View {
        VStack(spacing: 4) {
            HStack {
                Text(settings.t("Kullanım", "Usage"))
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                column(Text(Image(systemName: "arrow.down")).foregroundColor(NetworkColors.down))
                column(Text(Image(systemName: "arrow.up")).foregroundColor(NetworkColors.up))
                column(Text(settings.t("Toplam", "Total")).foregroundColor(.secondary))
            }
            ForEach(totals) { total in
                HStack {
                    Text(total.title)
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                    Spacer()
                    column(Text(size(total.down)))
                    column(Text(size(total.up)))
                    column(Text(size(total.down + total.up)).fontWeight(.semibold))
                }
            }
        }
    }

    private func column(_ text: Text) -> some View {
        text.font(.system(size: 10.5))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: 62, alignment: .trailing)
    }

    private func size(_ bytes: Double) -> String {
        NetworkInfo.formatBytes(bytes, turkish: settings.isTurkish)
    }

    private var hoveredStart: Date? {
        hoverTime.flatMap(buckets.start(at:))
    }

    private var summary: some View {
        let shown = hoveredStart
        let selected = shown.map { s in buckets.bars.filter { $0.time == s } } ?? buckets.bars
        let down = selected.filter(\.isDown).reduce(0) { $0 + $1.bytes }
        let up = selected.filter { !$0.isDown }.reduce(0) { $0 + $1.bytes }
        let title = shown.map { buckets.title(for: $0, locale: locale) } ?? settings.t("Bu aralıkta", "In this range")
        return HStack(spacing: 8) {
            Text(title).foregroundColor(.secondary)
            Spacer()
            Text("↓ \(size(down))").foregroundColor(NetworkColors.down)
            Text("↑ \(size(up))").foregroundColor(NetworkColors.up)
        }
        .font(.system(size: 10))
        .monospacedDigit()
        .lineLimit(1)
    }

    // MARK: - Data

    /// Works out everything once per load, so hovering and redrawing never walk the samples.
    /// The full history stays in memory only for the length of this call.
    private func reload() {
        let samples = NetworkHistory.shared.load()
        totals = makeTotals(samples)
        buckets = NetworkBuckets(samples: samples, unit: range.unit, count: range.bucketCount)
    }

    private func makeTotals(_ samples: [NetworkSample]) -> [Total] {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let week = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        let month = calendar.dateInterval(of: .month, for: now)?.start ?? today
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: month) ?? month

        var rows: [(from: Date, to: Date, total: Total)] = [
            (today, now.addingTimeInterval(1), Total(title: settings.t("Bugün", "Today"))),
            (yesterday, today, Total(title: settings.t("Dün", "Yesterday"))),
            (week, now.addingTimeInterval(1), Total(title: settings.t("Bu hafta", "This week"))),
            (month, now.addingTimeInterval(1), Total(title: settings.t("Bu ay", "This month"))),
            (lastMonth, month, Total(title: settings.t("Geçen ay", "Last month"))),
        ]
        for sample in samples where sample.time >= lastMonth || sample.time >= week {
            for i in rows.indices where sample.time >= rows[i].from && sample.time < rows[i].to {
                rows[i].total.down += sample.downBytes
                rows[i].total.up += sample.upBytes
            }
        }
        return rows.map(\.total)
    }
}
