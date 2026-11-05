import AppKit

/// The update flow on screen: the daily check, the question, the progress panel and the messages.
@MainActor
final class UpdateController {
    static let shared = UpdateController()

    private static let checkEvery: TimeInterval = 24 * 3600
    private let settings = AppSettings.shared
    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private var isBusy = false

    private init() {}

    /// MacMonitor stays open for days, so the daily check cannot rely on launches alone. The hourly
    /// timer only compares dates; a failed check (no network yet) is retried on the next tick.
    func start() {
        guard timer == nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in self?.checkIfDue() }
        let t = Timer(timeInterval: 3600, repeats: true) { _ in
            MainActor.assumeIsolated { UpdateController.shared.checkIfDue() }
        }
        t.tolerance = 600
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func checkIfDue() {
        guard settings.autoCheckUpdates, !isBusy, NSApp.modalWindow == nil else { return }
        let last = Date(timeIntervalSince1970: defaults.double(forKey: "lastUpdateCheck"))
        guard Date().timeIntervalSince(last) >= Self.checkEvery else { return }
        Task {
            guard case .newer(let release) = await checkNow(),
                  defaults.string(forKey: "skippedUpdateVersion") != release.version else { return }
            offer(release)
        }
    }

    /// Looks without asking anything; the About window shows the result itself
    func checkNow() async -> UpdateChecker.Outcome {
        isBusy = true
        defer { isBusy = false }
        let outcome = await UpdateChecker.check()
        if case .failed = outcome { return outcome }
        defaults.set(Date().timeIntervalSince1970, forKey: "lastUpdateCheck")
        return outcome
    }

    /// From the right-click menu: always says the result
    func checkFromMenu() {
        guard !isBusy else { return }
        Task {
            switch await checkNow() {
            case .newer(let release):
                offer(release)
            case .upToDate(let version):
                inform(settings.t("MacMonitor güncel", "MacMonitor is up to date"),
                       settings.t("Kullandığınız sürüm (\(version)) en son sürüm.",
                                  "The version you are using (\(version)) is the latest."))
            case .failed(let reason):
                inform(settings.t("Güncellemeler denetlenemedi", "Could not check for updates"), reason)
            }
        }
    }

    func offer(_ release: UpdateChecker.Release) {
        let canInstall = release.archive != nil && release.checksum != nil && Updater.canReplaceApp
        let alert = NSAlert()
        alert.messageText = settings.t("MacMonitor \(release.version) hazır", "MacMonitor \(release.version) is available")
        alert.informativeText = settings.t(
            "Kullandığınız sürüm: \(UpdateChecker.currentVersion). Güncelleme indirilir, doğrulanır ve MacMonitor yeniden başlatılır; pil geçmişiniz korunur.",
            "You are using \(UpdateChecker.currentVersion). The update is downloaded and verified, then MacMonitor restarts; your battery history is kept."
        )
        let notes = UpdateChecker.whatsNew(in: release.notes, turkish: settings.isTurkish)
        if !notes.isEmpty { alert.accessoryView = notesView(notes) }
        alert.addButton(withTitle: canInstall ? settings.t("Şimdi Güncelle", "Update Now")
                                              : settings.t("İndirme Sayfasını Aç", "Open Download Page"))
        alert.addButton(withTitle: settings.t("Sonra", "Later"))
        alert.addButton(withTitle: settings.t("Bu Sürümü Atla", "Skip This Version"))
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if canInstall { install(release) } else { NSWorkspace.shared.open(release.page) }
        case .alertThirdButtonReturn:
            defaults.set(release.version, forKey: "skippedUpdateVersion")
        default:
            break
        }
    }

    private func notesView(_ notes: String) -> NSView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 160))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let text = NSTextView(frame: scroll.contentView.bounds)
        text.isEditable = false
        text.autoresizingMask = [.width]
        text.textContainerInset = NSSize(width: 6, height: 6)
        text.font = .systemFont(ofSize: 12)
        text.string = notes
        scroll.documentView = text
        return scroll
    }

    private func install(_ release: UpdateChecker.Release) {
        isBusy = true
        let panel = UpdateProgressPanel(
            title: settings.t("MacMonitor güncelleniyor", "Updating MacMonitor"),
            message: settings.t("Sürüm \(release.version) indiriliyor ve doğrulanıyor…",
                                "Downloading and verifying version \(release.version)…"),
            cancelTitle: settings.t("Vazgeç", "Cancel")
        )
        let work = Task {
            do {
                try await Updater.install(release)
                panel.close()
                Updater.relaunch()
            } catch is CancellationError {
                panel.close()
                isBusy = false
            } catch {
                panel.close()
                isBusy = false
                inform(settings.t("Güncelleme kurulamadı", "The update could not be installed"),
                       message(for: error) + "\n\n" + settings.t(
                           "Dilerseniz yeni sürümü indirme sayfasından elle kurabilirsiniz.",
                           "You can install the new version by hand from the download page."),
                       page: release.page)
            }
        }
        panel.onCancel = { work.cancel() }
        panel.show()
    }

    private func message(for error: Error) -> String {
        guard let failure = error as? Updater.Failure else { return error.localizedDescription }
        switch failure {
        case .missingFiles:
            return settings.t("Bu sürümde \(UpdateChecker.archiveName) ya da özet dosyası yok.",
                              "This release has no \(UpdateChecker.archiveName) or checksum file.")
        case .http(let code):
            return settings.t("GitLab yanıtı: HTTP \(code)", "GitLab answered: HTTP \(code)")
        case .unreadableChecksum:
            return settings.t("Özet dosyası okunamadı.", "The checksum file could not be read.")
        case .checksumMismatch:
            return settings.t("İndirilen dosyanın özeti tutmuyor; dosya bozuk ya da değiştirilmiş olabilir.",
                              "The download does not match its checksum; it may be damaged or altered.")
        case .unpackFailed:
            return settings.t("Arşiv açılamadı.", "The archive could not be unpacked.")
        case .wrongApp:
            return settings.t("Arşivdeki uygulama beklenen MacMonitor sürümü değil.",
                              "The app in the archive is not the expected MacMonitor version.")
        case .badSignature:
            return settings.t("Uygulamanın imzası doğrulanamadı.", "The app's signature could not be verified.")
        case .notWritable(let folder, let reason):
            return settings.t("\(folder) klasörüne yazılamadı: \(reason)", "Could not write to \(folder): \(reason)")
        }
    }

    private func inform(_ title: String, _ detail: String, page: URL? = nil) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: settings.t("Tamam", "OK"))
        if page != nil { alert.addButton(withTitle: settings.t("İndirme Sayfasını Aç", "Open Download Page")) }
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn, let page { NSWorkspace.shared.open(page) }
    }
}

/// A small window with a spinner while the update downloads. Not a sheet: it is closed before the
/// app quits, and the menu bar app has no window to attach one to anyway.
@MainActor
private final class UpdateProgressPanel: NSObject {
    var onCancel: (() -> Void)?
    private let panel: NSPanel

    init(title: String, message: String, cancelTitle: String) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 92),
                        styleMask: [.titled], backing: .buffered, defer: false)
        super.init()
        panel.title = title
        panel.level = .floating
        panel.isReleasedWhenClosed = false

        let spinner = NSProgressIndicator(frame: NSRect(x: 20, y: 52, width: 20, height: 20))
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.startAnimation(nil)

        let label = NSTextField(labelWithString: message)
        label.frame = NSRect(x: 48, y: 52, width: 276, height: 20)
        label.lineBreakMode = .byTruncatingTail

        let button = NSButton(title: cancelTitle, target: self, action: #selector(cancel))
        button.sizeToFit()
        button.setFrameOrigin(NSPoint(x: 324 - button.frame.width, y: 12))

        panel.contentView?.addSubview(spinner)
        panel.contentView?.addSubview(label)
        panel.contentView?.addSubview(button)
    }

    func show() {
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel.close()
    }

    @objc private func cancel() {
        onCancel?()
    }
}
