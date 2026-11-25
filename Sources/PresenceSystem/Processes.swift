import Darwin
import PresenceCore

/// Name, parent and start time of a process, or nil when it is gone or not ours to read.
func processInfo(_ pid: Int32) -> ProcessInfoRecord? {
    guard pid > 0 else { return nil }
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
    let longName = cString(&info.pbi_name)
    let name = longName.isEmpty ? cString(&info.pbi_comm) : longName
    let started = Int64(info.pbi_start_tvsec) * 1_000 + Int64(info.pbi_start_tvusec) / 1_000
    return ProcessInfoRecord(name: name, ppid: Int32(bitPattern: info.pbi_ppid), startedAtMs: started)
}

/// Whether a process with this short name (`p_comm`) is running: one sysctl over the process table.
func processRunning(_ name: String) -> Bool? {
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
    var length = 0
    guard sysctl(&mib, 3, nil, &length, nil, 0) == 0 else { return nil }
    let stride = MemoryLayout<kinfo_proc>.stride
    // The table can grow between the two calls.
    var table = [kinfo_proc](repeating: kinfo_proc(), count: length / stride + 64)
    length = table.count * stride
    guard sysctl(&mib, 3, &table, &length, nil, 0) == 0 else { return nil }
    let wanted = String(name.prefix(Int(MAXCOMLEN)))
    for index in 0..<(length / stride) where cString(&table[index].kp_proc.p_comm) == wanted {
        return true
    }
    return false
}

private func cString<T>(_ tuple: inout T) -> String {
    withUnsafeBytes(of: &tuple) { raw in
        let bytes = raw.bindMemory(to: UInt8.self)
        let end = bytes.firstIndex(of: 0) ?? bytes.count
        return String(decoding: bytes[..<end], as: UTF8.self)
    }
}
