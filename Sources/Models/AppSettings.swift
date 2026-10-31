import Foundation
import Combine

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
    case cpuOnly = "cpuOnly"    // CPU only
    case ramOnly = "ramOnly"    // RAM only
    
    public var id: String { rawValue }
    
    public func title(isTurkish: Bool) -> String {
        switch self {
        case .icons:
            return isTurkish ? "Simgeli (Donanım CPU & RAM İkonları)" : "Icons (Hardware CPU & RAM Symbols)"
        case .compact:
            return isTurkish ? "Metinli (CPU 14%  RAM 52%)" : "Text (CPU 14%  RAM 52%)"
        case .minimal:
            return isTurkish ? "Sade Yüzdeler (14% · 52%)" : "Minimal Percentages (14% · 52%)"
        case .cpuOnly:
            return isTurkish ? "Sadece CPU" : "CPU Only"
        case .ramOnly:
            return isTurkish ? "Sadece RAM" : "RAM Only"
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
    
    @Published public var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: "launchAtLogin")
            LaunchAtLoginHelper.isEnabled = launchAtLogin
        }
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
        
        let savedStyle = defaults.string(forKey: "menuBarStyle") ?? MenuBarStyle.icons.rawValue
        self.menuBarStyle = MenuBarStyle(rawValue: savedStyle) ?? .icons
        
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
        
        self.launchAtLogin = LaunchAtLoginHelper.isEnabled
    }
}
