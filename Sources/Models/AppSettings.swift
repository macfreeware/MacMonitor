import Foundation
import Combine
import ServiceManagement

public enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case tr = "tr"
    case en = "en"
    
    public var id: String { rawValue }
    
    public func title(isTurkish: Bool) -> String {
        switch self {
        case .system:
            return isTurkish ? "🌐 Sistem Varsayılanı" : "🌐 System Default"
        case .tr:
            return "🇹🇷 Türkçe"
        case .en:
            return "🇬🇧 English"
        }
    }
}

public enum MenuBarStyle: String, CaseIterable, Identifiable {
    case icons = "icons"        // SF Symbol cpu & memorychip
    case compact = "compact"    // CPU 14%  RAM 52%
    case minimal = "minimal"    // 14% · 52%
    
    public var id: String { rawValue }
    
    public func title(isTurkish: Bool) -> String {
        switch self {
        case .icons:
            return isTurkish ? "Simgeli" : "Icons"
        case .compact:
            return isTurkish ? "Metinli" : "Text"
        case .minimal:
            return isTurkish ? "Sade" : "Minimal"
        }
    }
}

public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()
    
    private let defaults = UserDefaults.standard
    
    @Published public var appLanguage: AppLanguage {
        didSet {
            defaults.set(appLanguage.rawValue, forKey: "appLanguage")
        }
    }
    
    public var isTurkish: Bool {
        switch appLanguage {
        case .tr:
            return true
        case .en:
            return false
        case .system:
            let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
            return preferred.hasPrefix("tr")
        }
    }
    
    public func t(_ tr: String, _ en: String) -> String {
        return isTurkish ? tr : en
    }
    
    @Published public var refreshInterval: Double {
        didSet {
            defaults.set(refreshInterval, forKey: "refreshInterval")
        }
    }
    
    @Published public var menuBarStyle: MenuBarStyle {
        didSet {
            defaults.set(menuBarStyle.rawValue, forKey: "menuBarStyle")
        }
    }
    
    @Published public var cpuAlertThreshold: Double {
        didSet {
            defaults.set(cpuAlertThreshold, forKey: "cpuAlertThreshold")
        }
    }
    
    @Published public var ramAlertThreshold: Double {
        didSet {
            defaults.set(ramAlertThreshold, forKey: "ramAlertThreshold")
        }
    }
    
    @Published public var showColoredAlert: Bool {
        didSet {
            defaults.set(showColoredAlert, forKey: "showColoredAlert")
        }
    }
    
    @Published public var showSparkline: Bool {
        didSet {
            defaults.set(showSparkline, forKey: "showSparkline")
        }
    }
    
    @Published public var showCPUInMenuBar: Bool {
        didSet {
            defaults.set(showCPUInMenuBar, forKey: "showCPUInMenuBar")
        }
    }
    
    @Published public var showRAMInMenuBar: Bool {
        didSet {
            defaults.set(showRAMInMenuBar, forKey: "showRAMInMenuBar")
        }
    }
    
    /// Download and upload speed in the menu bar
    @Published public var showNetworkInMenuBar: Bool {
        didSet {
            defaults.set(showNetworkInMenuBar, forKey: "showNetworkInMenuBar")
        }
    }
    
    /// Network speed in Mbit/s, as internet plans are sold, instead of MB/s
    @Published public var showSpeedInBits: Bool {
        didSet {
            defaults.set(showSpeedInBits, forKey: "showSpeedInBits")
        }
    }
    
    public func formatSpeed(_ bytesPerSecond: Double) -> String {
        NetworkInfo.formatSpeed(bytesPerSecond, turkish: isTurkish, bits: showSpeedInBits)
    }
    
    /// Once a day MacMonitor asks GitLab whether a newer release exists
    @Published public var autoCheckUpdates: Bool {
        didSet {
            defaults.set(autoCheckUpdates, forKey: "autoCheckUpdates")
        }
    }
    
    /// Shows the real login item registration (SMAppService), not a stored preference.
    @Published public var launchAtLogin: Bool {
        didSet {
            guard !isSyncingLaunchAtLogin else { return }
            defaults.set(launchAtLogin, forKey: "launchAtLogin")
            LaunchAtLoginHelper.isEnabled = launchAtLogin
            // Turned off by the user in System Settings: approval has to be given there
            if launchAtLogin && SMAppService.mainApp.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
            refreshLaunchAtLoginStatus()
        }
    }
    private var isSyncingLaunchAtLogin = false
    
    /// Syncs the toggle with macOS (e.g. after a change in System Settings or a failed registration).
    public func refreshLaunchAtLoginStatus() {
        let enabled = LaunchAtLoginHelper.isEnabled
        guard launchAtLogin != enabled else { return }
        isSyncingLaunchAtLogin = true
        launchAtLogin = enabled
        isSyncingLaunchAtLogin = false
    }
    
    @Published public var activeTab: Int = 0
    
    public var targetPopoverHeight: CGFloat {
        switch activeTab {
        case 0:
            return showSparkline ? 542.0 : 398.0
        case 1:
            return 485.0
        case 2:
            return 485.0
        default:
            return 485.0
        }
    }
    
    private init() {
        let savedLang = defaults.string(forKey: "appLanguage") ?? AppLanguage.system.rawValue
        self.appLanguage = AppLanguage(rawValue: savedLang) ?? .system
        
        let savedInterval = defaults.double(forKey: "refreshInterval")
        self.refreshInterval = savedInterval > 0 ? savedInterval : 2.0
        
        // Before 1.4.0 "CPU only" and "RAM only" were styles; now each item is chosen on its own
        let savedStyle = defaults.string(forKey: "menuBarStyle") ?? MenuBarStyle.icons.rawValue
        self.menuBarStyle = MenuBarStyle(rawValue: savedStyle) ?? .icons
        self.showCPUInMenuBar = defaults.object(forKey: "showCPUInMenuBar") != nil
            ? defaults.bool(forKey: "showCPUInMenuBar") : savedStyle != "ramOnly"
        self.showRAMInMenuBar = defaults.object(forKey: "showRAMInMenuBar") != nil
            ? defaults.bool(forKey: "showRAMInMenuBar") : savedStyle != "cpuOnly"
        
        let savedCpuAlert = defaults.double(forKey: "cpuAlertThreshold")
        self.cpuAlertThreshold = savedCpuAlert > 0 ? savedCpuAlert : 85.0
        
        let savedRamAlert = defaults.double(forKey: "ramAlertThreshold")
        self.ramAlertThreshold = savedRamAlert > 0 ? savedRamAlert : 90.0
        
        if defaults.object(forKey: "showColoredAlert") != nil {
            self.showColoredAlert = defaults.bool(forKey: "showColoredAlert")
        } else {
            self.showColoredAlert = true
        }
        
        if defaults.object(forKey: "showSparkline") != nil {
            self.showSparkline = defaults.bool(forKey: "showSparkline")
        } else {
            self.showSparkline = true
        }
        
        if defaults.object(forKey: "showNetworkInMenuBar") != nil {
            self.showNetworkInMenuBar = defaults.bool(forKey: "showNetworkInMenuBar")
        } else {
            self.showNetworkInMenuBar = true
        }
        
        self.showSpeedInBits = defaults.bool(forKey: "showSpeedInBits")
        
        if defaults.object(forKey: "autoCheckUpdates") != nil {
            self.autoCheckUpdates = defaults.bool(forKey: "autoCheckUpdates")
        } else {
            self.autoCheckUpdates = true
        }
        
        // On by default, applied once; not from a translocated (quarantined, unmoved) copy
        let isTranslocated = Bundle.main.bundlePath.contains("/AppTranslocation/")
        let userTurnedOff = defaults.object(forKey: "launchAtLogin") != nil && !defaults.bool(forKey: "launchAtLogin")
        if !isTranslocated && !defaults.bool(forKey: "launchAtLoginDefaultApplied") {
            defaults.set(true, forKey: "launchAtLoginDefaultApplied")
            if !userTurnedOff {
                LaunchAtLoginHelper.isEnabled = true
            }
        }
        self.launchAtLogin = LaunchAtLoginHelper.isEnabled
    }
}
