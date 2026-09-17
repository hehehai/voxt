import Darwin
import Foundation
import MLX

nonisolated enum MeetingFileResourceTelemetry {
    static func log(stage: String, startedAt: Date? = nil) {
        var info = task_vm_info_data_t()
        let capacity = MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        var count = mach_msg_type_number_t(capacity)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        let footprint = status == KERN_SUCCESS ? String(info.phys_footprint / 1_048_576) : "unavailable"
        let elapsed = startedAt.map { String(format: "%.2f", Date().timeIntervalSince($0)) } ?? "0"
        VoxtLog.meeting("File resources. stage=\(stage), footprintMiB=\(footprint), mlxActiveMiB=\(Memory.activeMemory / 1_048_576), mlxCacheMiB=\(Memory.cacheMemory / 1_048_576), elapsedSeconds=\(elapsed), thermal=\(ProcessInfo.processInfo.thermalState.rawValue)")
    }
}
