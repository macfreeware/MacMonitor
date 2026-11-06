import SwiftUI
import Charts

/// Clock-aligned ticks and date formats shared by the history charts
enum HistoryAxis {
    private static let steps: [TimeInterval] = [
        5 * 60, 15 * 60, 30 * 60, 3_600, 2 * 3_600, 3 * 3_600, 6 * 3_600, 12 * 3_600,
        86_400, 2 * 86_400, 7 * 86_400, 14 * 86_400, 30 * 86_400, 90 * 86_400,
    ]

    static func step(span: TimeInterval, desired: Int) -> TimeInterval {
        steps.first { span / $0 <= Double(desired) } ?? steps[steps.count - 1]
    }

    /// On the local clock (:00, :15 … or midnight), not counted from the range's start
    static func ticks(start: Date, end: Date, desired: Int) -> [Date] {
        let step = step(span: end.timeIntervalSince(start), desired: desired)
        let offset = TimeInterval(TimeZone.current.secondsFromGMT(for: start))
        var t = ((start.timeIntervalSince1970 + offset) / step).rounded(.up) * step - offset
        var dates: [Date] = []
        while t <= end.timeIntervalSince1970 {
            dates.append(Date(timeIntervalSince1970: t))
            t += step
        }
        return dates
    }

    /// A label right at the end of the axis would be cut off
    static func hasRoom(_ date: Date, start: Date, end: Date) -> Bool {
        end.timeIntervalSince(date) > end.timeIntervalSince(start) * 0.06
    }

    static func timeFormat(_ locale: Locale) -> Date.FormatStyle {
        // Turkish reads 24-hour; English keeps AM/PM, which .omitted would drop
        (locale.identifier.hasPrefix("tr")
            ? Date.FormatStyle.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
            : Date.FormatStyle.dateTime.hour().minute()).locale(locale)
    }

    static func labelFormat(span: TimeInterval, desired: Int, locale: Locale) -> Date.FormatStyle {
        step(span: span, desired: desired) < 86_400
            ? timeFormat(locale)
            : Date.FormatStyle.dateTime.day().month(.abbreviated).locale(locale)
    }

    static func rangeTitle(start: Date, end: Date, locale: Locale) -> String {
        let format = Date.FormatStyle.dateTime.day().month(.abbreviated).year().locale(locale)
        let time = timeFormat(locale)
        return "\(start.formatted(format)) \(start.formatted(time)) – \(end.formatted(format)) \(end.formatted(time))"
    }
}

/// Reports the time under the pointer and, in the detail windows, turns a drag into a zoom
struct ChartPointerOverlay: View {
    let proxy: ChartProxy
    @Binding var hoverTime: Date?
    var onZoom: ((Date, Date) -> Void)? = nil

    @State private var dragStart: CGFloat? = nil
    @State private var dragNow: CGFloat? = nil

    var body: some View {
        GeometryReader { geo in
            let plot = geo[proxy.plotAreaFrame]
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            hoverTime = proxy.value(atX: location.x - plot.origin.x, as: Date.self)
                        case .ended:
                            hoverTime = nil
                        }
                    }
                    .gesture(onZoom == nil ? nil : drag(plot))
                if let a = dragStart, let b = dragNow {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.18))
                        .frame(width: abs(b - a), height: plot.height)
                        .offset(x: min(a, b) + plot.origin.x, y: plot.origin.y)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private func drag(_ plot: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                dragStart = clamp(value.startLocation.x - plot.origin.x, plot)
                dragNow = clamp(value.location.x - plot.origin.x, plot)
            }
            .onEnded { _ in
                defer { dragStart = nil; dragNow = nil }
                guard let a = dragStart, let b = dragNow, abs(b - a) >= 6,
                      let from = proxy.value(atX: min(a, b), as: Date.self),
                      let to = proxy.value(atX: max(a, b), as: Date.self) else { return }
                onZoom?(from, to)
            }
    }

    private func clamp(_ x: CGFloat, _ plot: CGRect) -> CGFloat {
        min(max(x, 0), plot.width)
    }
}

/// The range shown in a detail window: a preset length, moved back and forth or zoomed by dragging
struct HistoryViewport: Equatable {
    var span: TimeInterval
    /// nil means "up to now"
    var end: Date? = nil

    var isLive: Bool { end == nil }

    func bounds(now: Date) -> (from: Date, to: Date) {
        let to = end ?? now
        return (to.addingTimeInterval(-span), to)
    }

    mutating func move(by direction: Double, now: Date) {
        let target = bounds(now: now).to.addingTimeInterval(direction * span)
        end = target >= now ? nil : target
    }
}

struct HistoryPreset: Identifiable {
    let id: Int
    let title: String
    /// nil means everything recorded
    let span: TimeInterval?
}

/// The preset ranges; none is highlighted after zooming to a custom range
struct HistoryRangeBar: View {
    let presets: [HistoryPreset]
    let selection: Int?
    let onSelect: (HistoryPreset) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(presets) { preset in
                let isSelected = preset.id == selection
                Button(action: { onSelect(preset) }) {
                    Text(preset.title)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? .white : .primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.08)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .focusable(false)  // no keyboard focus ring around a button that was not chosen
            }
            Spacer()
        }
    }
}

/// Back, forward and "now" buttons with the current range next to them
struct HistoryNavigationBar: View {
    @ObservedObject var settings: AppSettings
    @Binding var viewport: HistoryViewport
    let earliest: Date?
    let onChange: () -> Void

    private var locale: Locale { Locale(identifier: settings.t("tr_TR", "en_US")) }

    var body: some View {
        let now = Date()
        let bounds = viewport.bounds(now: now)
        HStack(spacing: 6) {
            Button { viewport.move(by: -1, now: now); onChange() } label: { Image(systemName: "chevron.left") }
                .disabled(earliest.map { bounds.from <= $0 } ?? true)
                .focusable(false)
                .help(settings.t("Önceki aralık", "Previous range"))
            Button { viewport.move(by: 1, now: now); onChange() } label: { Image(systemName: "chevron.right") }
                .disabled(viewport.isLive)
                .focusable(false)
                .help(settings.t("Sonraki aralık", "Next range"))
            Button(settings.t("Şimdi", "Now")) { viewport.end = nil; onChange() }
                .disabled(viewport.isLive)
                .focusable(false)
            Text(HistoryAxis.rangeTitle(start: bounds.from, end: bounds.to, locale: locale))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer()
            // A range longer than the history stays that long, and this says why it is partly empty
            if let earliest, earliest > bounds.from, earliest < bounds.to {
                let start = "\(earliest.formatted(Date.FormatStyle.dateTime.day().month(.abbreviated).locale(locale))) \(earliest.formatted(HistoryAxis.timeFormat(locale)))"
                Text(settings.t("Kayıtların başlangıcı: \(start)", "Records start: \(start)"))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Text(settings.t("Yakınlaştırmak için grafikte sürükleyin", "Drag on the chart to zoom in"))
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .controlSize(.small)
    }
}

/// A titled block in the right column of a detail window
struct DetailCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold).monospacedDigit()
        }
        .font(.system(size: 11))
        .lineLimit(1)
    }
}
