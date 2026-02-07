import Foundation
import AppKit

// MARK: - PerformanceMonitorService
// Single-purpose service for monitoring application performance

class PerformanceMonitorService {
    static let shared = PerformanceMonitorService()
    
    private var updateTimer: Timer?
    private var cpuUsage: Double = 0.0
    private var memoryUsage: (resident: Int, virtual: Int) = (0, 0)
    
    // CPU tracking state
    private var previousTotalTime: Double = 0
    private var previousTimestamp: TimeInterval = 0
    
    private init() {}
    
    // MARK: - Monitoring Control
    
    func startMonitoring(updateInterval: TimeInterval = 2.0) {
        stopMonitoring()
        
        // Take initial CPU sample
        let (totalTime, _) = sampleThreadCPUTime()
        previousTotalTime = totalTime
        previousTimestamp = ProcessInfo.processInfo.systemUptime
        
        updateTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.updateMetrics()
        }
        
        // Initial update
        updateMetrics()
    }
    
    func stopMonitoring() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    // MARK: - Metrics
    
    func getMemoryUsage() -> (resident: String, virtual: String) {
        return (
            ByteCountFormatter.string(fromByteCount: Int64(memoryUsage.resident), countStyle: .memory),
            ByteCountFormatter.string(fromByteCount: Int64(memoryUsage.virtual), countStyle: .memory)
        )
    }
    
    func getRawMemoryUsage() -> (resident: Int, virtual: Int) {
        return memoryUsage
    }
    
    func getCPUUsage() -> Double {
        return cpuUsage
    }
    
    func getSystemMemory() -> String {
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        return ByteCountFormatter.string(fromByteCount: Int64(physicalMemory), countStyle: .memory)
    }
    
    func getProcessorCount() -> Int {
        return ProcessInfo.processInfo.processorCount
    }
    
    func getSystemVersion() -> String {
        return ProcessInfo.processInfo.operatingSystemVersionString
    }
    
    func getAppVersion() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        return "\(version) (\(build))"
    }
    
    func getProcessID() -> Int {
        return Int(ProcessInfo.processInfo.processIdentifier)
    }
    
    func getUptime() -> String {
        let uptime = ProcessInfo.processInfo.systemUptime
        return formatUptime(uptime)
    }
    
    // MARK: - Private Methods
    
    private func updateMetrics() {
        updateMemoryUsage()
        updateCPUUsage()
    }
    
    private func updateMemoryUsage() {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if result == KERN_SUCCESS {
            memoryUsage = (
                resident: Int(info.resident_size),
                virtual: Int(info.virtual_size)
            )
        }
    }
    
    /// Sample total CPU time across all threads in seconds
    private func sampleThreadCPUTime() -> (totalSeconds: Double, threadCount: Int) {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        
        let result = task_threads(mach_task_self_, &threadList, &threadCount)
        guard result == KERN_SUCCESS, let threads = threadList else {
            return (0, 0)
        }
        
        defer {
            // Deallocate the thread list
            let size = vm_size_t(MemoryLayout<thread_t>.size * Int(threadCount))
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), size)
        }
        
        var totalTime: Double = 0
        
        for i in 0..<Int(threadCount) {
            var info = thread_basic_info()
            var infoCount = mach_msg_type_number_t(MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<natural_t>.size)
            
            let threadResult = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &infoCount)
                }
            }
            
            if threadResult == KERN_SUCCESS {
                // Skip idle threads
                if info.flags & TH_FLAGS_IDLE == 0 {
                    let userTime = Double(info.user_time.seconds) + Double(info.user_time.microseconds) / 1_000_000.0
                    let systemTime = Double(info.system_time.seconds) + Double(info.system_time.microseconds) / 1_000_000.0
                    totalTime += userTime + systemTime
                }
            }
        }
        
        return (totalTime, Int(threadCount))
    }
    
    private func updateCPUUsage() {
        let now = ProcessInfo.processInfo.systemUptime
        let (currentTotalTime, _) = sampleThreadCPUTime()
        
        let elapsedWall = now - previousTimestamp
        let elapsedCPU = currentTotalTime - previousTotalTime
        
        if elapsedWall > 0 {
            // CPU usage as percentage of a single core; divide by core count for overall %
            let rawPercent = (elapsedCPU / elapsedWall) * 100.0
            cpuUsage = min(max(rawPercent, 0), 100.0 * Double(ProcessInfo.processInfo.processorCount))
        }
        
        previousTotalTime = currentTotalTime
        previousTimestamp = now
    }
    
    private func formatUptime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m \(secs)s"
        } else if minutes > 0 {
            return "\(minutes)m \(secs)s"
        } else {
            return "\(secs)s"
        }
    }
}
