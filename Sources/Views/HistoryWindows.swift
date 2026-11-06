import SwiftUI
import AppKit

/// Independent, resizable windows for reading the battery and network histories in detail.
/// While one is open MacMonitor shows in the Dock, so the window can be reached with Cmd-Tab.
@MainActor
final class HistoryWindowManager: NSObject, NSWindowDelegate {
    enum Kind: String {
        case battery, network
    }

    static let shared = HistoryWindowManager()

    private var windows: [Kind: NSWindow] = [:]

    private override init() {
        super.init()
    }

    func show(_ kind: Kind) {
        NotificationCenter.default.post(name: .closeMacMonitorPopover, object: nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = windows[kind] {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let settings = AppSettings.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 660),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentMinSize = NSSize(width: 820, height: 520)
        let host: NSViewController
        switch kind {
        case .battery:
            window.title = settings.t("Pil Geçmişi", "Battery History")
            host = NSHostingController(rootView: BatteryDetailView(settings: settings))
        case .network:
            window.title = settings.t("Ağ Geçmişi", "Network History")
            host = NSHostingController(rootView: NetworkDetailView(settings: settings))
        }
        window.contentViewController = host
        window.setContentSize(NSSize(width: 1000, height: 660))
        window.center()
        window.setFrameAutosaveName("MacMonitorHistory.\(kind.rawValue)")
        windows[kind] = window
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let kind = windows.first(where: { $0.value === window })?.key else { return }
        // Drops the view and with it the loaded history
        window.contentViewController = nil
        windows[kind] = nil
        if windows.isEmpty { NSApp.setActivationPolicy(.accessory) }
    }
}

/// The small button in a history card's corner that opens the detail window
struct HistoryExpandButton: View {
    @ObservedObject var settings: AppSettings
    let kind: HistoryWindowManager.Kind

    var body: some View {
        Button(action: { HistoryWindowManager.shared.show(kind) }) {
            HStack(spacing: 3) {
                Text(settings.t("Ayrıntılar", "Details"))
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 8, weight: .semibold))
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.accentColor)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .help(settings.t("Ayrı pencerede ayrıntılı incele", "Explore in a separate window"))
    }
}
