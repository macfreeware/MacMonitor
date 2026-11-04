import AppKit
import SwiftUI
import Combine

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var cancellables = Set<AnyCancellable>()
    
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var popoverOpenTime = Date.distantPast
    private var lastStatusSignature = ""
    
    private let monitor = SystemMonitor.shared
    private let settings = AppSettings.shared
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent dock icon from showing
        NSApp.setActivationPolicy(.accessory)
        
        setupPopover()
        setupStatusItem()
        observeUpdates()
        BatteryHistory.shared.start()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        BatteryHistory.shared.flush()
    }
    
    private func setupPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
    }
    
    /// The SwiftUI content exists only while the popover is shown; otherwise every metric
    /// update would re-render the hidden view tree and cost CPU in the background.
    private func attachPopoverContent() {
        guard popover.contentViewController == nil else { return }
        let contentView = PopoverContentView(monitor: monitor, settings: settings) { [weak self] measuredHeight in
            self?.applyPopoverHeight(measuredHeight)
        }
        popover.contentViewController = NSHostingController(rootView: contentView)
    }
    
    private func measureAndUpdatePopoverHeight() {
        guard let hc = popover.contentViewController as? NSHostingController<PopoverContentView> else { return }
        let fit = hc.sizeThatFits(in: NSSize(width: 350, height: 10000))
        if fit.height > 100 {
            applyPopoverHeight(ceil(fit.height))
        }
    }
    
    private func applyPopoverHeight(_ rawHeight: CGFloat) {
        guard rawHeight > 100 else { return }
        let targetHeight = ceil(rawHeight)
        let window = popover.contentViewController?.view.window
        let screen = window?.screen ?? statusItem?.button?.window?.screen ?? NSScreen.main
        let maxAllowedTopY = screen?.visibleFrame.maxY
        let previousTopY: CGFloat? = {
            guard let win = window, popover.isShown else { return nil }
            if let limitY = maxAllowedTopY {
                return min(win.frame.maxY, limitY)
            }
            return win.frame.maxY
        }()
        
        if abs(popover.contentSize.height - targetHeight) > 0.5 {
            popover.contentSize = NSSize(width: 350, height: targetHeight)
        }
        
        if popover.isShown, let win = popover.contentViewController?.view.window {
            let anchorTopY = previousTopY ?? maxAllowedTopY ?? win.frame.maxY
            var frame = win.frame
            if abs(frame.maxY - anchorTopY) > 0.5 || (maxAllowedTopY != nil && frame.maxY > maxAllowedTopY!) {
                let clampedTopY = maxAllowedTopY != nil ? min(anchorTopY, maxAllowedTopY!) : anchorTopY
                frame.origin.y = clampedTopY - frame.height
                win.setFrame(frame, display: true, animate: false)
            }
        }
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        
        updateStatusItemLength()
        updateButtonDisplay()
    }
    
    private func observeUpdates() {
        // Observe menu bar style changes to lock status item width
        settings.$menuBarStyle
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusItemLength()
                self?.updateButtonDisplay()
            }
            .store(in: &cancellables)
            
        // Observe metric changes
        Publishers.CombineLatest3(
            monitor.$menuBarText,
            monitor.$isCpuAlert,
            monitor.$isRamAlert
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.updateButtonDisplay()
        }
        .store(in: &cancellables)
        
        // Observe active tab, sparkline toggle, and language to keep popover height & top anchor locked
        Publishers.CombineLatest3(
            settings.$activeTab,
            settings.$showSparkline,
            settings.$appLanguage
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.measureAndUpdatePopoverHeight()
        }
        .store(in: &cancellables)
        
        // Close popover when standalone About window opens
        NotificationCenter.default.publisher(for: .closeMacMonitorPopover)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.closePopover()
            }
            .store(in: &cancellables)
    }
    
    /// Fixed width for the widest content ("100%") so the item never jumps as values change
    private func updateStatusItemLength() {
        let widest = makeStatusItemAttributedTitle(cpuVal: 100, ramVal: 100, isCpuAlert: false, isRamAlert: false)
        statusItem.length = ceil(widest.size().width) + 10
        statusItem.button?.alignment = .center
    }
    
    private func updateButtonDisplay() {
        guard let button = statusItem.button else { return }
        // Several publishers fire per refresh; redraw only when what is shown actually changes
        let signature = "\(settings.menuBarStyle.rawValue)|\(Int(round(monitor.cpuInfo.totalUsage)))|\(Int(round(monitor.memoryInfo.usedPercentage)))|\(monitor.isCpuAlert && settings.showColoredAlert)|\(monitor.isRamAlert && settings.showColoredAlert)"
        guard signature != lastStatusSignature else { return }
        lastStatusSignature = signature
        button.attributedTitle = makeStatusItemAttributedTitle(
            cpuVal: Int(round(monitor.cpuInfo.totalUsage)),
            ramVal: Int(round(monitor.memoryInfo.usedPercentage)),
            isCpuAlert: monitor.isCpuAlert && settings.showColoredAlert,
            isRamAlert: monitor.isRamAlert && settings.showColoredAlert
        )
    }
    
    private func makeStatusItemAttributedTitle(cpuVal: Int, ramVal: Int, isCpuAlert: Bool, isRamAlert: Bool) -> NSAttributedString {

        let font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
        let normalColor = NSColor.labelColor
        let alertColor = NSColor.systemRed
        
        // Pad single-digit numbers with typographic figure space (\u{2007})
        // In monospaced digit fonts, \u{2007} has the exact same width as digits 0-9
        func formatPercent(_ val: Int) -> String {
            if val < 10 {
                return "\u{2007}\(val)%"
            }
            return "\(val)%"
        }
        
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        let result = NSMutableAttributedString()
        
        func makeAttachment(systemName: String, isAlert: Bool) -> NSAttributedString {
            guard let symbol = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)?.withSymbolConfiguration(symbolConfig) else {
                return NSAttributedString()
            }
            // Natural symbol size, tinted when drawn so labelColor follows the menu bar appearance
            let color = isAlert ? alertColor : normalColor
            let img = NSImage(size: symbol.size, flipped: false) { rect in
                symbol.draw(in: rect)
                color.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            let attach = NSTextAttachment()
            attach.image = img
            attach.bounds = CGRect(x: 0, y: ((font.capHeight - symbol.size.height) / 2).rounded(), width: symbol.size.width, height: symbol.size.height)
            return NSAttributedString(attachment: attach)
        }
        
        switch settings.menuBarStyle {
        case .icons:
            // Native CPU hardware icon + %
            result.append(makeAttachment(systemName: "cpu", isAlert: isCpuAlert))
            result.append(NSAttributedString(string: " \(formatPercent(cpuVal))  ", attributes: [
                .font: font,
                .foregroundColor: isCpuAlert ? alertColor : normalColor
            ]))
            // Native RAM memory module icon + %
            result.append(makeAttachment(systemName: "memorychip", isAlert: isRamAlert))
            result.append(NSAttributedString(string: " \(formatPercent(ramVal))", attributes: [
                .font: font,
                .foregroundColor: isRamAlert ? alertColor : normalColor
            ]))
            
        case .compact:
            result.append(NSAttributedString(string: "CPU \(formatPercent(cpuVal))  RAM \(formatPercent(ramVal))", attributes: [
                .font: font,
                .foregroundColor: (isCpuAlert || isRamAlert) ? alertColor : normalColor
            ]))
            
        case .minimal:
            result.append(NSAttributedString(string: "\(formatPercent(cpuVal)) · \(formatPercent(ramVal))", attributes: [
                .font: font,
                .foregroundColor: (isCpuAlert || isRamAlert) ? alertColor : normalColor
            ]))
            
        case .cpuOnly:
            result.append(makeAttachment(systemName: "cpu", isAlert: isCpuAlert))
            result.append(NSAttributedString(string: " \(formatPercent(cpuVal))", attributes: [
                .font: font,
                .foregroundColor: isCpuAlert ? alertColor : normalColor
            ]))
            
        case .ramOnly:
            result.append(makeAttachment(systemName: "memorychip", isAlert: isRamAlert))
            result.append(NSAttributedString(string: " \(formatPercent(ramVal))", attributes: [
                .font: font,
                .foregroundColor: isRamAlert ? alertColor : normalColor
            ]))
        }
        
        return result
    }
    
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        
        if event.type == .rightMouseUp || (event.type == .leftMouseUp && event.modifierFlags.contains(.control)) {
            showContextMenu()
        } else {
            togglePopover()
        }
    }
    
    private func togglePopover() {
        guard let button = statusItem.button else { return }
        
        if popover.isShown {
            closePopover()
        } else {
            settings.refreshLaunchAtLoginStatus()
            attachPopoverContent()
            measureAndUpdatePopoverHeight()
            popoverOpenTime = Date()
            
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeFirstResponder(nil)
            measureAndUpdatePopoverHeight()
            startEventMonitors()
        }
    }
    
    private func closePopover() {
        if popover.isShown {
            popover.performClose(nil)
        }
        stopEventMonitors()
    }
    
    private func startEventMonitors() {
        stopEventMonitors()
        
        // 1. Global Monitor: Captures clicks outside our application window (desktop, other apps)
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self else { return }
            // Ignore click events within 300ms of opening to avoid instant dismissal race conditions
            guard Date().timeIntervalSince(self.popoverOpenTime) > 0.3 else { return }
            Task { @MainActor in
                if self.popover.isShown {
                    self.closePopover()
                }
            }
        }
        
        // 2. Local Monitor: Captures clicks inside our app process but outside the popover window
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self else { return event }
            guard Date().timeIntervalSince(self.popoverOpenTime) > 0.3 else { return event }
            if self.popover.isShown {
                // If clicked on status bar button, let the button handle click toggle
                if let button = self.statusItem.button, button.window == event.window {
                    return event
                }
                // If clicked inside popover window, allow normal interaction
                if self.popover.contentViewController?.view.window == event.window {
                    return event
                }
                // Click is outside popover
                self.closePopover()
            }
            return event
        }
    }
    
    private func stopEventMonitors() {
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
    }
    
    private func showContextMenu() {
        closePopover()
        let menu = NSMenu()
        
        let openItem = NSMenuItem(
            title: settings.t("MacMonitor Detaylarını Aç", "Open MacMonitor Details"),
            action: #selector(menuOpenPopover),
            keyEquivalent: "o"
        )
        openItem.target = self
        openItem.image = NSImage(systemSymbolName: "gauge.with.dots.needle.67percent", accessibilityDescription: nil)
        menu.addItem(openItem)
        
        let aboutItem = NSMenuItem(
            title: settings.t("Hakkında Penceresini Aç...", "Open About Window..."),
            action: #selector(menuOpenAbout),
            keyEquivalent: "i"
        )
        aboutItem.target = self
        aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        menu.addItem(aboutItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let refreshItem = NSMenuItem(
            title: settings.t("Şimdi Yenile", "Refresh Now"),
            action: #selector(menuRefresh),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        refreshItem.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
        menu.addItem(refreshItem)
        
        let activityItem = NSMenuItem(
            title: settings.t("Etkinlik Monitörünü Aç...", "Open Activity Monitor..."),
            action: #selector(menuOpenActivityMonitor),
            keyEquivalent: "a"
        )
        activityItem.target = self
        activityItem.image = NSImage(systemSymbolName: "waveform.path.ecg.rectangle", accessibilityDescription: nil)
        menu.addItem(activityItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(
            title: settings.t("MacMonitor'dan Çık", "Quit MacMonitor"),
            action: #selector(menuQuit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quitItem)
        
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // Reset menu immediately so left clicks work for popover
        statusItem.menu = nil
    }
    
    @objc private func menuOpenPopover() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.togglePopover()
        }
    }
    
    @objc private func menuRefresh() {
        monitor.refreshMetrics()
    }
    
    @objc private func menuOpenActivityMonitor() {
        let path = "/System/Applications/Utilities/Activity Monitor.app"
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
    
    @objc private func menuOpenAbout() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            AboutWindowManager.shared.show()
        }
    }
    
    @objc private func menuQuit() {
        closePopover()
        NSApp.activate(ignoringOtherApps: true)
        
        let alert = NSAlert()
        alert.messageText = settings.t(
            "MacMonitor'dan çıkmak istiyor musunuz?",
            "Are you sure you want to quit MacMonitor?"
        )
        alert.informativeText = settings.t(
            "Uygulama kapatıldığında menü çubuğundaki CPU ve RAM takibi sonlandırılacaktır.",
            "CPU and RAM monitoring in the menu bar will stop when the application quits."
        )
        alert.alertStyle = .warning
        
        // Button 1 (Default button - Enter / Space target): "Vazgeç" / "Cancel"
        alert.addButton(withTitle: settings.t("Vazgeç", "Cancel"))
        
        // Button 2 (Secondary destructive action): "Çıkış Yap" / "Quit"
        let quitButton = alert.addButton(withTitle: settings.t("Çıkış Yap", "Quit"))
        if #available(macOS 11.0, *) {
            quitButton.hasDestructiveAction = true
        }
        
        if alert.runModal() == .alertSecondButtonReturn {
            NSApplication.shared.terminate(nil)
        }
    }
    
    // MARK: - NSPopoverDelegate
    nonisolated public func popoverWillShow(_ notification: Notification) {
        Task { @MainActor in
            self.monitor.isPopoverOpen = true
        }
    }
    
    nonisolated public func popoverDidClose(_ notification: Notification) {
        Task { @MainActor in
            self.monitor.isPopoverOpen = false
            self.stopEventMonitors()
            self.popover.contentViewController = nil
        }
    }
}
