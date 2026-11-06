import SwiftUI

/// The battery history card in the panel; the detail window opens from its corner button
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

    @AppStorage("batteryHistoryRange") private var rangeRaw: Int = Range.day.rawValue
    @State private var model = BatteryChartModel()
    @State private var hoverTime: Date? = nil

    // New samples arrive once a minute; refresh the chart at the same pace while it is visible
    private let timer = Timer.publish(every: BatteryHistory.interval, on: .main, in: .common).autoconnect()

    public init(settings: AppSettings) {
        self.settings = settings
    }

    private var range: Range { Range(rawValue: rangeRaw) ?? .day }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(settings.t("Pil geçmişi", "Battery history"))
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                HistoryExpandButton(settings: settings, kind: .battery)
            }
            // Five ranges do not fit next to the title, so the picker gets its own row
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
            .frame(maxWidth: .infinity)

            if model.points.count < 2 {
                Text(settings.t("Geçmiş birikiyor: MacMonitor pili dakikada bir kaydeder.",
                                "History is building up: MacMonitor records the battery once a minute."))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 130, alignment: .center)
            } else {
                BatteryPercentChart(model: model, settings: settings, hoverTime: $hoverTime)
                    .frame(height: 130)
                if model.points.contains(where: { $0.watts != nil }) {
                    BatteryWattsChart(model: model, hoverTime: $hoverTime)
                        .frame(height: 48)
                }
                BatteryLegend(model: model, settings: settings)
                summary
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .onAppear(perform: reload)
        .onChange(of: rangeRaw) { _ in reload() }
        .onReceive(timer) { _ in reload() }
    }

    /// The full history stays in memory only for the length of this call
    private func reload() {
        let samples = BatteryHistory.shared.load()
        let now = Date()
        let from = range.seconds.map { now.addingTimeInterval(-$0) } ?? samples.first?.time ?? now
        model = BatteryChartModel(samples: samples, from: from, to: now, maxPoints: 360)
    }

    private var summary: some View {
        var parts: [String] = []
        if let low = model.minPercent {
            parts.append(settings.t("En düşük ", "Lowest ") + "\(low)%")
        }
        if let w = model.avgDrainWatts {
            parts.append(settings.t("pilde ort. ", "avg. on battery ") + BatteryInfo.formatWatts(w))
        }
        return Text(verbatim: parts.joined(separator: " · "))
            .font(.system(size: 9))
            .foregroundColor(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}
