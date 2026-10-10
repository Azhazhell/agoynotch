//
//  SystemStatsMonitor.swift
//  AgoyNotch
//
//  CPU usage % and memory used for the expanded panel's top row. Local-only: reads the
//  public mach host statistics (`host_statistics` HOST_CPU_LOAD_INFO for aggregate CPU
//  ticks, `host_statistics64` HOST_VM_INFO64 for memory pages) — no SMC, no private APIs,
//  nothing leaves the Mac. Memory pressure (Activity Monitor's green/yellow/red) comes from
//  the public sysctl `kern.memorystatus_vm_pressure_level`, polled in the same loop.
//  Samples every 1.5 s, and ONLY while the panel is expanded (NotchViewModel calls
//  start()/stop() on expand/collapse) to save battery.
//

import Foundation
import Darwin

@MainActor
final class SystemStatsMonitor: ObservableObject {

    enum MemoryPressure: Equatable { case normal, warning, critical }

    /// Aggregate CPU usage across all cores, 0–100. Nil until the first tick delta exists.
    @Published private(set) var cpuPercent: Double?
    /// Memory used, matching Activity Monitor's "Memory Used" (App + Wired + Compressed).
    @Published private(set) var ramUsedBytes: UInt64?
    /// Kernel memory-pressure level (Activity Monitor's green/yellow/red). `.normal` if unknown.
    @Published private(set) var memoryPressure: MemoryPressure = .normal
    /// Installed physical memory.
    let ramTotalBytes: UInt64 = ProcessInfo.processInfo.physicalMemory

    /// Sampling interval while expanded, in nanoseconds.
    static let interval: UInt64 = 1_500_000_000

    /// Fetched once: every `mach_host_self()` call adds a send right to the host port.
    private let host: host_t = mach_host_self()
    /// CPU ticks from the previous sample; usage is the delta between two samples.
    private var lastTicks: (busy: UInt32, total: UInt32)?
    private var samplingTask: Task<Void, Never>?

    // MARK: - Lifecycle

    /// Starts sampling (no-op if already running). RAM and memory pressure are read
    /// immediately; CPU shows `--%` until the first tick delta ~0.5 s later.
    func start() {
        guard samplingTask == nil else { return }
        cpuPercent = nil
        lastTicks = readCPUTicks()
        sampleRAM()
        samplePressure()
        samplingTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            while !Task.isCancelled {
                self?.sample()
                try? await Task.sleep(nanoseconds: SystemStatsMonitor.interval)
            }
        }
    }

    /// Stops sampling and clears CPU so a reopen never shows the previous session's value
    /// (shows `--%` until the first fresh delta). RAM/pressure are re-read synchronously on
    /// the next start().
    func stop() {
        samplingTask?.cancel()
        samplingTask = nil
        cpuPercent = nil
        lastTicks = nil
    }

    // MARK: - Formatting (numbers only, no labels)

    /// e.g. `23%`; `--%` before the first value.
    var cpuText: String {
        cpuPercent.map { "\(Int($0.rounded()))%" } ?? "--%"
    }

    /// Used GB with one decimal, e.g. `11.2G`; `--G` before the first value.
    var ramText: String {
        ramUsedBytes.map { String(format: "%.1fG", Double($0) / 1_073_741_824) } ?? "--G"
    }

    /// Hidden VoiceOver label, e.g. "CPU 23 percent, memory used 11.2 gigabytes".
    var accessibilityText: String {
        let cpu = cpuPercent.map { "CPU \(Int($0.rounded())) percent" } ?? "CPU unavailable"
        let ram = ramUsedBytes.map {
            String(format: "memory used %.1f gigabytes", Double($0) / 1_073_741_824)
        } ?? "memory used unavailable"
        let pressure = memoryPressure == .normal ? "" : ", memory pressure high"
        return "\(cpu), \(ram)\(pressure)"
    }

    // MARK: - Sampling

    private func sample() {
        if let now = readCPUTicks() {
            if let last = lastTicks {
                // natural_t tick counters can wrap: use wrapping arithmetic.
                let dBusy = now.busy &- last.busy
                let dTotal = now.total &- last.total
                if dTotal > 0 {
                    let value = min(max(Double(dBusy) / Double(dTotal) * 100, 0), 100)
                    if cpuPercent != value { cpuPercent = value }
                }
            }
            lastTicks = now
        }
        sampleRAM()
        samplePressure()
    }

    /// `kern.memorystatus_vm_pressure_level` (public sysctl, Int32): 1 normal, 2 warning,
    /// 4 critical. Falls back to `.normal` if unavailable.
    private func samplePressure() {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size  // size_t
        let rc = sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
        let value: MemoryPressure
        if rc != 0 || size != MemoryLayout<Int32>.size {
            value = .normal
        } else {
            switch level {
            case 4: value = .critical
            case 2: value = .warning
            default: value = .normal
            }
        }
        if memoryPressure != value { memoryPressure = value }
    }

    /// Aggregate (all cores) busy and total ticks. HOST_CPU_LOAD_INFO fills a caller-owned
    /// struct, so there is nothing to vm_deallocate (unlike host_processor_info).
    private func readCPUTicks() -> (busy: UInt32, total: UInt32)? {
        var info = host_cpu_load_info_data_t()
        // HOST_CPU_LOAD_INFO_COUNT is a C macro that isn't imported into Swift.
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        // cpu_ticks is indexed by CPU_STATE_USER (0), SYSTEM (1), IDLE (2), NICE (3).
        let user = info.cpu_ticks.0
        let system = info.cpu_ticks.1
        let idle = info.cpu_ticks.2
        let nice = info.cpu_ticks.3
        let busy = user &+ system &+ nice
        return (busy, busy &+ idle)
    }

    /// Memory used = App Memory (internal − purgeable) + Wired + Compressed, in bytes.
    private func sampleRAM() {
        var stats = vm_statistics64_data_t()
        // HOST_VM_INFO64_COUNT is a C macro that isn't imported into Swift.
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return }
        let page = UInt64(vm_kernel_page_size)
        let internalPages = UInt64(stats.internal_page_count)
        let app = internalPages - min(UInt64(stats.purgeable_count), internalPages)
        let pages = app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        let used = min(pages * page, ramTotalBytes)
        if ramUsedBytes != used { ramUsedBytes = used }
    }
}
