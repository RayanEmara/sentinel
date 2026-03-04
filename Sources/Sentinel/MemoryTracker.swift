import Foundation

struct MemoryTracker {
    static func report(location: String) {
        #if DEBUG
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            let mb = Double(info.resident_size) / 1048576.0
            print("[Memory] \(location): \(String(format: "%.2f", mb)) MB")
        }
        #endif
    }
}
