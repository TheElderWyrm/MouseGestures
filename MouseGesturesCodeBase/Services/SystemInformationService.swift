import Foundation
import AppKit

// MARK: - System Information Service
// Single-purpose service for gathering system and performance information

class SystemInformationService {
    static let shared = SystemInformationService()

    private init() {}

    // MARK: - Memory Information

    func getMemoryUsage() -> (resident: Int, virtual: Int)? {
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

        guard result == KERN_SUCCESS else { return nil }
        return (resident: Int(info.resident_size), virtual: Int(info.virtual_size))
    }

    func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(bytes))
    }

    // MARK: - CPU Information

    func getCPUUsage() -> Double? {
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

        guard result == KERN_SUCCESS else { return nil }

        // Calculate CPU usage percentage
        // Note: This is a simplified calculation
        // time_value_t has two properties: seconds (integer_t) and microseconds (integer_t)
        let userTime = Double(info.user_time.seconds) + Double(info.user_time.microseconds) / 1_000_000.0
        let systemTime = Double(info.system_time.seconds) + Double(info.system_time.microseconds) / 1_000_000.0
        let totalTime = userTime + systemTime

        return totalTime
    }

    // MARK: - Process Information

    func getProcessUptime() -> TimeInterval {
        return ProcessInfo.processInfo.systemUptime
    }

    func formatUptime(_ uptime: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: uptime) ?? "Unknown"
    }

    // MARK: - System Metrics

    func getSystemMetrics() -> SystemMetrics {
        let memoryUsage = getMemoryUsage()
        let cpuUsage = getCPUUsage()
        let uptime = getProcessUptime()

        return SystemMetrics(
            memoryResident: memoryUsage?.resident ?? 0,
            memoryVirtual: memoryUsage?.virtual ?? 0,
            cpuTime: cpuUsage ?? 0,
            uptime: uptime,
            timestamp: Date()
        )
    }

    // MARK: - Thread Information

    func getThreadCount() -> Int {
        var threads: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0

        let result = task_threads(mach_task_self_, &threads, &threadCount)

        guard result == KERN_SUCCESS else { return 0 }

        // Clean up
        if let threads = threads {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.size))
        }

        return Int(threadCount)
    }

    // MARK: - Disk Usage

    func getAppDiskUsage() -> Int64? {
        let appURL = Bundle.main.bundleURL

        // `.totalFileAllocatedSize` on the bundle *directory* only describes the
        // directory entry itself (a few KB), not its contents, so the old code
        // reported an essentially meaningless size for the app. Sum the
        // allocated size of every regular file inside the bundle instead. Do
        // NOT pass `.skipsPackageDescendants`: the app bundle is itself a
        // package and we want to descend into it (and any nested packages).
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: appURL,
            includingPropertiesForKeys: keys,
            options: []
        ) else { return nil }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            // Prefer allocated-on-disk size; fall back to the logical file size.
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }
}

// MARK: - System Metrics Model

struct SystemMetrics {
    let memoryResident: Int
    let memoryVirtual: Int
    let cpuTime: Double
    let uptime: TimeInterval
    let timestamp: Date
}
