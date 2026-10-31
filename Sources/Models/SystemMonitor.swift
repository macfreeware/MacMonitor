import Foundation
import Darwin
import Combine
import AppKit

private struct CPULoadRaw {
    var user: UInt64
    var system: UInt64
    var idle: UInt64
    var nice: UInt64
}

private struct ProcessSnapRaw {
    var cpuTime: UInt64
    var timestamp: Date
}

@MainActor
public final class SystemMonitor: ObservableObject {
    public static let shared = SystemMonitor()
    
    @Published public private(set) var cpuInfo = CPUInfo()
    @Published public private(set) var memoryInfo = MemoryInfo()
    @Published public private(set) var topCPUProcesses: [ProcessItem] = []
    @Published public private(set) var topMemoryProcesses: [ProcessItem] = []
    @Published public private(set) var menuBarText: String = "..."
    @Published public private(set) var isCpuAlert: Bool = false
    @Published public private(set) var isRamAlert: Bool = false
    
    /// Popover state - when closed, process scanning is disabled to preserve CPU/battery!
    public var isPopoverOpen: Bool = false {
        didSet {
            if isPopoverOpen {
                // Immediately refresh processes when user clicks popover
                updateProcesses()
            } else {
                // Clear process tracking buffers to save memory
                prevProcessSnaps.removeAll()
            }
        }
    }
    
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    // CPU delta tracking
    private var previousCPULoads: [CPULoadRaw]?
    private var previousCPUTime: Date?
    
    // Process delta tracking
    private var prevProcessSnaps: [pid_t: ProcessSnapRaw] = [:]
    
    // Static system info
    private let totalRAM: UInt64
    private let numCores: Int
    private let hostPort = mach_host_self()
    private let pathBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: Int(MAXPATHLEN))
    // pti_total_user/system are Mach time units (24 MHz ticks on Apple Silicon), not nanoseconds
    private let machTicksToNs: Double = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return tb.denom > 0 ? Double(tb.numer) / Double(tb.denom) : 1.0
    }()
    
    private init() {
        self.totalRAM = SystemInfoHelper.totalPhysicalMemory
        self.numCores = SystemInfoHelper.coreCount
        
        // Initial immediate fetch
        resetHistory(interval: AppSettings.shared.refreshInterval)
        refreshMetrics()
        
        // Listen to settings changes to reschedule timer
        AppSettings.shared.$refreshInterval
            .dropFirst()
            .sink { [weak self] newInterval in
                self?.resetHistory(interval: newInterval)
                self?.startTimer(interval: newInterval)
            }
            .store(in: &cancellables)
            
        AppSettings.shared.$menuBarStyle
            .sink { [weak self] _ in
                self?.updateMenuBarDisplay()
            }
            .store(in: &cancellables)
            
        AppSettings.shared.$cpuAlertThreshold
            .sink { [weak self] _ in
                self?.evaluateAlerts()
            }
            .store(in: &cancellables)
            
        AppSettings.shared.$ramAlertThreshold
            .sink { [weak self] _ in
                self?.evaluateAlerts()
            }
            .store(in: &cancellables)
        
        startTimer(interval: AppSettings.shared.refreshInterval)
    }
    
    deinit {
        pathBuffer.deallocate()
        timer?.invalidate()
    }
    
    public func startTimer(interval: Double) {
        timer?.invalidate()
        let safeInterval = max(0.5, interval)
        let t = Timer(timeInterval: safeInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshMetrics()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        self.timer = t
    }
    
    /// Number of samples that cover the last 60 seconds at the given refresh interval
    private static func historyLength(for interval: Double) -> Int {
        return max(10, Int((60.0 / max(0.5, interval)).rounded()))
    }
    
    private func resetHistory(interval: Double) {
        let length = Self.historyLength(for: interval)
        cpuInfo.history = Array(repeating: 0.0, count: length)
        memoryInfo.history = Array(repeating: memoryInfo.usedPercentage, count: length)
    }
    
    public func refreshMetrics() {
        updateMemory()
        updateCPU()
        
        if isPopoverOpen {
            updateProcesses()
        }
        
        evaluateAlerts()
        updateMenuBarDisplay()
    }
    
    // MARK: - Memory Update (Direct Mach kernel host_statistics64)
    private func updateMemory() {
        var vmStat = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        
        let kernReturn = withUnsafeMutablePointer(to: &vmStat) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(self.hostPort, HOST_VM_INFO64, $0, &count)
            }
        }
        
        guard kernReturn == KERN_SUCCESS else { return }
        
        let pageSize = UInt64(vm_kernel_page_size)
        // Same split as Activity Monitor: App Memory = anonymous (internal) pages minus purgeable
        let internalPages = UInt64(vmStat.internal_page_count)
        let purgeablePages = UInt64(vmStat.purgeable_count)
        let active = (internalPages > purgeablePages ? internalPages - purgeablePages : 0) * pageSize
        let wired = UInt64(vmStat.wire_count) * pageSize
        let compressed = UInt64(vmStat.compressor_page_count) * pageSize
        let inactive = UInt64(vmStat.inactive_count) * pageSize
        let free = UInt64(vmStat.free_count) * pageSize
        // File cache and everything not counted as used
        let cached = self.totalRAM > active + wired + compressed + free ? self.totalRAM - active - wired - compressed - free : inactive
        
        // Memory Used = App Memory + Wired + Compressed
        let used = active + wired + compressed
        
        // Swap usage via sysctl
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        let hasSwap = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0
        
        var mem = self.memoryInfo
        mem.totalBytes = self.totalRAM
        mem.usedBytes = used
        mem.activeBytes = active
        mem.wiredBytes = wired
        mem.compressedBytes = compressed
        mem.inactiveBytes = cached
        mem.freeBytes = free
        
        if hasSwap {
            mem.swapUsedBytes = UInt64(swap.xsu_used)
            mem.swapTotalBytes = UInt64(swap.xsu_total)
        }
        
        // Update history (last 60 seconds)
        var hist = mem.history
        let length = Self.historyLength(for: AppSettings.shared.refreshInterval)
        if hist.count >= length { hist.removeFirst(hist.count - length + 1) }
        hist.append(mem.usedPercentage)
        mem.history = hist
        
        self.memoryInfo = mem
    }
    
    // MARK: - CPU Update (Direct Mach kernel host_processor_info)
    private func updateCPU() {
        var numCPUs: natural_t = 0
        var cpuInfoPtr: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0
        
        let res = host_processor_info(self.hostPort, PROCESSOR_CPU_LOAD_INFO, &numCPUs, &cpuInfoPtr, &numCpuInfo)
        guard res == KERN_SUCCESS, let cpuInfo = cpuInfoPtr else { return }
        
        defer {
            let size = vm_size_t(numCpuInfo) * vm_size_t(MemoryLayout<integer_t>.size)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), size)
        }
        
        let coreCount = Int(numCPUs)
        var currentLoads: [CPULoadRaw] = []
        currentLoads.reserveCapacity(coreCount)
        
        for i in 0..<coreCount {
            let base = i * Int(CPU_STATE_MAX)
            let user = UInt64(cpuInfo[base + Int(CPU_STATE_USER)])
            let system = UInt64(cpuInfo[base + Int(CPU_STATE_SYSTEM)])
            let idle = UInt64(cpuInfo[base + Int(CPU_STATE_IDLE)])
            let nice = UInt64(cpuInfo[base + Int(CPU_STATE_NICE)])
            currentLoads.append(CPULoadRaw(user: user, system: system, idle: idle, nice: nice))
        }
        
        let now = Date()
        defer {
            self.previousCPULoads = currentLoads
            self.previousCPUTime = now
        }
        
        guard let prevLoads = self.previousCPULoads, prevLoads.count == coreCount else {
            return
        }
        
        var totalUser: UInt64 = 0
        var totalSystem: UInt64 = 0
        var totalIdle: UInt64 = 0
        var totalNice: UInt64 = 0
        var perCoreUsages: [Double] = []
        perCoreUsages.reserveCapacity(coreCount)
        
        for i in 0..<coreCount {
            let u = currentLoads[i].user >= prevLoads[i].user ? currentLoads[i].user - prevLoads[i].user : 0
            let s = currentLoads[i].system >= prevLoads[i].system ? currentLoads[i].system - prevLoads[i].system : 0
            let id = currentLoads[i].idle >= prevLoads[i].idle ? currentLoads[i].idle - prevLoads[i].idle : 0
            let n = currentLoads[i].nice >= prevLoads[i].nice ? currentLoads[i].nice - prevLoads[i].nice : 0
            
            let total = u + s + id + n
            let active = u + s + n
            let pct = total > 0 ? (Double(active) / Double(total)) * 100.0 : 0.0
            perCoreUsages.append(min(100.0, max(0.0, pct)))
            
            totalUser += u
            totalSystem += s
            totalIdle += id
            totalNice += n
        }
        
        let totalTicks = totalUser + totalSystem + totalIdle + totalNice
        var cpu = self.cpuInfo
        if totalTicks > 0 {
            let activeTicks = totalUser + totalSystem + totalNice
            cpu.totalUsage = min(100.0, max(0.0, (Double(activeTicks) / Double(totalTicks)) * 100.0))
            cpu.userUsage = (Double(totalUser + totalNice) / Double(totalTicks)) * 100.0
            cpu.systemUsage = (Double(totalSystem) / Double(totalTicks)) * 100.0
            cpu.idleUsage = (Double(totalIdle) / Double(totalTicks)) * 100.0
        }
        cpu.coreUsages = perCoreUsages
        
        // Update history (last 60 seconds)
        var hist = cpu.history
        let length = Self.historyLength(for: AppSettings.shared.refreshInterval)
        if hist.count >= length { hist.removeFirst(hist.count - length + 1) }
        hist.append(cpu.totalUsage)
        cpu.history = hist
        
        self.cpuInfo = cpu
    }
    
    // MARK: - Process Update (Only runs while Popover is open)
    private func updateProcesses() {
        let maxPids = 2048
        var pids = [pid_t](repeating: 0, count: maxPids)
        let bytesUsed = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(MemoryLayout<pid_t>.size * maxPids))
        guard bytesUsed > 0 else { return }
        let count = Int(bytesUsed) / MemoryLayout<pid_t>.size
        
        let now = Date()
        var currentSnaps: [pid_t: ProcessSnapRaw] = [:]
        var candidateItems: [ProcessItem] = []
        candidateItems.reserveCapacity(128)
        
        for i in 0..<count {
            let pid = pids[i]
            if pid <= 0 { continue }
            
            var procInfo = proc_taskallinfo()
            let size = proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, &procInfo, Int32(MemoryLayout<proc_taskallinfo>.size))
            if size == MemoryLayout<proc_taskallinfo>.size {
                let cpuTime = procInfo.ptinfo.pti_total_user + procInfo.ptinfo.pti_total_system
                // Physical footprint is what Activity Monitor shows as "Memory"; fall back to resident size
                var usage = rusage_info_v2()
                let hasUsage = withUnsafeMutablePointer(to: &usage) {
                    $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                        proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) == 0
                    }
                }
                let memBytes = hasUsage ? usage.ri_phys_footprint : UInt64(procInfo.ptinfo.pti_resident_size)
                
                // Keep processes with at least 10MB memory or active CPU
                if memBytes > 10 * 1024 * 1024 || cpuTime > 0 {
                    currentSnaps[pid] = ProcessSnapRaw(cpuTime: cpuTime, timestamp: now)
                    
                    var cpuPct: Double = 0.0
                    if let prev = prevProcessSnaps[pid] {
                        let dt = now.timeIntervalSince(prev.timestamp)
                        if dt > 0.1 && cpuTime >= prev.cpuTime {
                            let deltaNs = Double(cpuTime - prev.cpuTime) * machTicksToNs
                            // Share of the whole CPU (all cores), same scale as the menu bar total;
                            // Activity Monitor would show this multiplied by the core count
                            cpuPct = (deltaNs / (dt * 1_000_000_000.0)) * 100.0 / Double(max(1, numCores))
                        }
                    }
                    
                    // Resolve process name
                    let pathLen = proc_pidpath(pid, self.pathBuffer, UInt32(MAXPATHLEN))
                    let name: String
                    if pathLen > 0 {
                        let fullPath = String(cString: self.pathBuffer)
                        name = URL(fileURLWithPath: fullPath).lastPathComponent
                    } else {
                        name = "PID \(pid)"
                    }
                    
                    candidateItems.append(ProcessItem(pid: pid, name: name, cpuPercent: cpuPct, memBytes: memBytes))
                }
            }
        }
        
        self.prevProcessSnaps = currentSnaps
        
        // Sort top lists
        let sortedByCPU = candidateItems.sorted { $0.cpuPercent > $1.cpuPercent }
        let sortedByMem = candidateItems.sorted { $0.memBytes > $1.memBytes }
        
        self.topCPUProcesses = Array(sortedByCPU.prefix(6))
        self.topMemoryProcesses = Array(sortedByMem.prefix(6))
    }
    
    // MARK: - Alerts and Menu Bar Formatting
    private func evaluateAlerts() {
        let settings = AppSettings.shared
        self.isCpuAlert = cpuInfo.totalUsage >= settings.cpuAlertThreshold
        self.isRamAlert = memoryInfo.usedPercentage >= settings.ramAlertThreshold
    }
    
    private func updateMenuBarDisplay() {
        let settings = AppSettings.shared
        let cpuVal = Int(round(cpuInfo.totalUsage))
        let ramVal = Int(round(memoryInfo.usedPercentage))
        
        switch settings.menuBarStyle {
        case .icons:
            self.menuBarText = "CPU \(cpuVal)%  RAM \(ramVal)%"
        case .compact:
            self.menuBarText = "CPU \(cpuVal)%  RAM \(ramVal)%"
        case .minimal:
            self.menuBarText = "\(cpuVal)% · \(ramVal)%"
        case .cpuOnly:
            self.menuBarText = "CPU \(cpuVal)%"
        case .ramOnly:
            self.menuBarText = "RAM \(ramVal)%"
        }
    }
}
