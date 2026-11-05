import AppKit

@main
@MainActor
struct MacMonitorMain {
    static func main() {
        #if DEBUG
        Updater.runSelfTestIfRequested()
        #endif
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
