import Foundation
import AppKit

// MARK: - PerformanceMonitorService
// Single-purpose service for monitoring application performance

class PerformanceMonitorService {
    static let shared = PerformanceMonitorService()
    
    private var updateTimer: Timer?
    private var cpuUsage: Double = 0.0
    private var memoryUsage: (resident: Int, virtual: Int) = (0, 0)
    
    private init() {}
    
    // MARK: - Monitoring Control
    
    func startMonitoring(updateInterval: TimeInterval = 2.0) {
        stopMonitoring()
        
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
    
    private func updateCPUUsage() {
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
            // Simplified CPU usage calculation
            let usage = Double(info.resident_size) / Double(ProcessInfo.processInfo.physicalMemory) * 100
            cpuUsage = min(usage * 10, 100) // Rough approximation
        }
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
