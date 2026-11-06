import SwiftUI

/// Battery history in its own window: larger charts, moving through time, zooming by dragging,
/// and a list of charging sessions
struct BatteryDetailView: View {
    @ObservedObject var settings: AppSettings

    @State private var viewport = HistoryViewport(span: 86_400)
    @State private var selectedPreset: Int? = 2  // 24 hours
    @State private var samples: [BatterySample] = []
    @State private var model = BatteryChartModel()
    @State private var hoverTime: Date? = nil

    private let timer = Timer.publish(every: BatteryHistory.interval, on: .main, in: .common).autoconnect()
    private var locale: Locale { Locale(identifier: settings.t("tr_TR", "en_US")) }

    private var presets: [HistoryPreset] {
        [
            HistoryPreset(id: 0, title: settings.t("1 saat", "1 hour"), span: 3_600),
            HistoryPreset(id: 1, title: settings.t("6 saat", "6 hours"), span: 6 * 3_600),
            HistoryPreset(id: 2, title: settings.t("24 saat", "24 hours"), span: 86_400),
            HistoryPreset(id: 3, title: settings.t("7 gün", "7 days"), span: 7 * 86_400),
            HistoryPreset(id: 4, title: settings.t("30 gün", "30 days"), span: 30 * 86_400),
            HistoryPreset(id: 5, title: settings.t("Tümü", "All"), span: nil),
        ]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HistoryRangeBar(presets: presets, selection: selectedPreset, onSelect: select)
                HistoryNavigationBar(settings: settings, viewport: $viewport,
                                     earliest: samples.first?.time, onChange: rebuild)
                if model.points.count < 2 {
                    Text(settings.t("Bu aralıkta kayıt yok.", "Nothing recorded in this range."))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    BatteryPercentChart(model: model, settings: settings, hoverTime: $hoverTime, large: true, onZoom: zoom)
                        .frame(maxHeight: .infinity)
                    if model.points.contains(where: { $0.watts != nil }) {
                        Text(settings.t("Sistem gücü", "System power"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        BatteryWattsChart(model: model, hoverTime: $hoverTime, large: true, onZoom: zoom)
                            .frame(height: 110)
                    }
                    BatteryLegend(model: model, settings: settings, fontSize: 11, compact: false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            sidebar.frame(width: 250)
        }
        .padding(14)
        .frame(minWidth: 820, maxWidth: .infinity, minHeight: 520, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear(perform: reload)
        .onReceive(timer) { _ in reload() }
    }

    private var sidebar: some View {
        VStack(spacing: 10) {
            DetailCard(title: settings.t("Bu aralıkta", "In this range")) {
                DetailRow(label: BatteryState.charging.title(settings), value: BatteryLegend.duration(model.chargingTime, settings))
                DetailRow(label: BatteryState.pluggedIn.title(settings), value: BatteryLegend.duration(model.pluggedTime, settings))
                DetailRow(label: BatteryState.onBattery.title(settings), value: BatteryLegend.duration(model.batteryTime, settings))
                if !model.screenSpans.isEmpty {
                    DetailRow(label: settings.t("Ekran açık", "Screen on"), value: BatteryLegend.duration(model.screenTime, settings))
                    DetailRow(label: settings.t("Pilde ekran açık", "Screen on, on battery"), value: BatteryLegend.duration(model.screenOnBatteryTime, settings))
                }
                if let low = model.minPercent, let high = model.maxPercent {
                    DetailRow(label: settings.t("En düşük · en yüksek", "Lowest · highest"), value: "\(low)% · \(high)%")
                }
                if let w = model.avgDrainWatts {
                    DetailRow(label: settings.t("Pilde ort. güç", "Avg. power on battery"), value: BatteryInfo.formatWatts(w))
                }
            }
            DetailCard(title: settings.t("Şarj oturumları (\(model.sessions.count))", "Charging sessions (\(model.sessions.count))")) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(model.sessions.reversed()) { session in
                            sessionRow(session)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func sessionRow(_ s: BatteryChartModel.Session) -> some View {
        let date = Date.FormatStyle.dateTime.day().month(.abbreviated).locale(locale)
        let time = HistoryAxis.timeFormat(locale)
        return Button(action: { focus(s) }) {
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text(verbatim: "\(s.start.formatted(date)) \(s.start.formatted(time))")
                    Spacer()
                    Text(verbatim: "\(s.fromPercent)% → \(s.toPercent)%")
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }
                Text(BatteryLegend.duration(s.end.timeIntervalSince(s.start), settings))
                    .foregroundColor(.secondary)
            }
            .font(.system(size: 10.5))
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .help(settings.t("Grafikte göster", "Show on the chart"))
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

    /// Shows a charging session with a little room on both sides
    private func focus(_ session: BatteryChartModel.Session) {
        let length = max(20 * 60, session.end.timeIntervalSince(session.start))
        zoom(session.start.addingTimeInterval(-length * 0.15), session.end.addingTimeInterval(length * 0.15))
    }

    private func reload() {
        samples = BatteryHistory.shared.load()
        rebuild()
    }

    private func rebuild() {
        hoverTime = nil
        let bounds = viewport.bounds(now: Date())
        model = BatteryChartModel(samples: samples, from: bounds.from, to: bounds.to, maxPoints: 900)
    }
}
