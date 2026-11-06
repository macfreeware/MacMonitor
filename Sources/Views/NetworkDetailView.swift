import SwiftUI

/// Network usage in its own window: a larger chart, moving through time, zooming by dragging,
/// and the numbers behind each bar
struct NetworkDetailView: View {
    @ObservedObject var settings: AppSettings

    @State private var viewport = HistoryViewport(span: 86_400)
    @State private var selectedPreset: Int? = 2  // 24 hours
    @State private var samples: [NetworkSample] = []
    @State private var buckets = NetworkBuckets()
    @State private var hoverTime: Date? = nil

    private let timer = Timer.publish(every: NetworkHistory.interval, on: .main, in: .common).autoconnect()
    private var locale: Locale { Locale(identifier: settings.t("tr_TR", "en_US")) }

    private var presets: [HistoryPreset] {
        [
            HistoryPreset(id: 0, title: settings.t("1 saat", "1 hour"), span: 3_600),
            HistoryPreset(id: 1, title: settings.t("6 saat", "6 hours"), span: 6 * 3_600),
            HistoryPreset(id: 2, title: settings.t("24 saat", "24 hours"), span: 86_400),
            HistoryPreset(id: 3, title: settings.t("7 gün", "7 days"), span: 7 * 86_400),
            HistoryPreset(id: 4, title: settings.t("30 gün", "30 days"), span: 30 * 86_400),
            HistoryPreset(id: 5, title: settings.t("12 ay", "12 months"), span: 365 * 86_400),
            HistoryPreset(id: 6, title: settings.t("Tümü", "All"), span: nil),
        ]
    }

    /// Bars stay readable at any range
    private static func unit(for span: TimeInterval) -> Calendar.Component {
        if span <= 6 * 3_600 { return .minute }
        if span <= 3 * 86_400 { return .hour }
        if span <= 100 * 86_400 { return .day }
        return .month
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HistoryRangeBar(presets: presets, selection: selectedPreset, onSelect: select)
                HistoryNavigationBar(settings: settings, viewport: $viewport,
                                     earliest: samples.first?.time, onChange: rebuild)
                if buckets.bars.isEmpty {
                    Text(settings.t("Bu aralıkta kayıt yok.", "Nothing recorded in this range."))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    NetworkBarChart(buckets: buckets, settings: settings, hoverTime: $hoverTime, large: true, onZoom: zoom)
                        .frame(maxHeight: .infinity)
                    hoverLine
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            sidebar.frame(width: 270)
        }
        .padding(14)
        .frame(minWidth: 820, maxWidth: .infinity, minHeight: 520, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear(perform: reload)
        .onReceive(timer) { _ in reload() }
    }

    /// Always there, so the chart does not change height as the pointer moves
    private var hoverLine: some View {
        let row = hoverTime.flatMap(buckets.start(at:)).flatMap { s in buckets.rows.first { $0.time == s } }
        return HStack(spacing: 10) {
            Text(row.map { buckets.title(for: $0.time, locale: locale) } ?? settings.t("Çubukların üzerine gelin", "Point at a bar"))
                .foregroundColor(.secondary)
            if let row {
                Text("↓ \(size(row.down))").foregroundColor(NetworkColors.down)
                Text("↑ \(size(row.up))").foregroundColor(NetworkColors.up)
                Text(size(row.down + row.up)).fontWeight(.semibold)
            }
            Spacer()
        }
        .font(.system(size: 11))
        .monospacedDigit()
        .frame(height: 16)
    }

    private var sidebar: some View {
        let down = buckets.rows.reduce(0) { $0 + $1.down }
        let up = buckets.rows.reduce(0) { $0 + $1.up }
        let busiest = buckets.rows.max { $0.down + $0.up < $1.down + $1.up }
        return VStack(spacing: 10) {
            DetailCard(title: settings.t("Bu aralıkta", "In this range")) {
                DetailRow(label: settings.t("İndirilen", "Downloaded"), value: size(down))
                DetailRow(label: settings.t("Yüklenen", "Uploaded"), value: size(up))
                DetailRow(label: settings.t("Toplam", "Total"), value: size(down + up))
                if let busiest {
                    DetailRow(label: settings.t("En yoğun", "Busiest"), value: buckets.title(for: busiest.time, locale: locale))
                }
            }
            DetailCard(title: settings.t("Dönemler (\(buckets.rows.count))", "Periods (\(buckets.rows.count))")) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(buckets.rows.reversed()) { row in
                            rowView(row)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func rowView(_ row: NetworkBuckets.Row) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(buckets.title(for: row.time, locale: locale))
                .foregroundColor(.secondary)
                .lineLimit(1)
            HStack(spacing: 8) {
                Text("↓ \(size(row.down))").foregroundColor(NetworkColors.down)
                Text("↑ \(size(row.up))").foregroundColor(NetworkColors.up)
                Spacer()
                Text(size(row.down + row.up)).fontWeight(.semibold)
            }
            .monospacedDigit()
        }
        .font(.system(size: 10.5))
    }

    private func size(_ bytes: Double) -> String {
        NetworkInfo.formatBytes(bytes, turkish: settings.isTurkish)
    }

    // MARK: - Range

    private func select(_ preset: HistoryPreset) {
        selectedPreset = preset.id
        let all = samples.first.map { max(3_600, Date().timeIntervalSince($0.time)) } ?? 86_400
        viewport = HistoryViewport(span: preset.span ?? all)
        rebuild()
    }

    private func zoom(_ from: Date, _ to: Date) {
        selectedPreset = nil
        viewport = HistoryViewport(span: max(10 * 60, to.timeIntervalSince(from)), end: min(to, Date()))
        rebuild()
    }

    private func reload() {
        samples = NetworkHistory.shared.load()
        rebuild()
    }

    private func rebuild() {
        hoverTime = nil
        let bounds = viewport.bounds(now: Date())
        buckets = NetworkBuckets(samples: samples, from: bounds.from, to: bounds.to, unit: Self.unit(for: viewport.span))
    }
}
