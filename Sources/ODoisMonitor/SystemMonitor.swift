import Darwin
import Foundation
import IOKit

/// Nível de pressão de memória informado pelo kernel (o mesmo do Monitor de Atividade).
enum MemoryPressureLevel: Int {
    case normal = 1, warning = 2, critical = 4

    var label: String {
        switch self {
        case .normal: return "Normal"
        case .warning: return "Atenção"
        case .critical: return "Crítica"
        }
    }
}

struct SystemSample {
    var date = Date()
    /// Uso total da CPU, de 0 a 1.
    var cpu: Double = 0
    var ramUsed: UInt64 = 0
    var ramTotal: UInt64 = 0
    var ramCompressed: UInt64 = 0
    var ramWired: UInt64 = 0
    var ramCached: UInt64 = 0
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0
    /// Pressão de memória de 0 a 1 (100% − memória livre segundo o kernel).
    var pressure: Double = 0
    var pressureLevel: MemoryPressureLevel = .normal
    /// Uso da GPU de 0 a 1; nil se o IOKit não informar.
    var gpu: Double?
    var gpuMemory: UInt64?
}

/// Consumo dos processos de uma CLI de LLM.
struct ProcessUsage: Identifiable, Equatable {
    let id: String
    var count = 0
    /// Soma de CPU dos processos, em % de um núcleo (pode passar de 100).
    var cpu: Double = 0
    var memory: UInt64 = 0
}

/// Lê CPU, RAM, pressão de memória e GPU a cada 2 s, com histórico de 2 min.
@MainActor
final class SystemMonitor: ObservableObject {
    static let historySize = 60
    static let shared = SystemMonitor()

    @Published private(set) var current = SystemSample()
    @Published private(set) var history: [SystemSample] = []
    @Published private(set) var processes: [ProcessUsage] = []

    private let sampler = Sampler()
    private let queue = DispatchQueue(label: "odois-monitor.system", qos: .utility)
    private var timer: Timer?

    init() {
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        queue.async { [sampler] in
            let sample = sampler.sample()
            let procs = sampler.llmProcesses()
            Task { @MainActor in
                self.current = sample
                self.history.append(sample)
                if self.history.count > Self.historySize {
                    self.history.removeFirst(self.history.count - Self.historySize)
                }
                self.processes = procs
            }
        }
    }
}

/// Leituras de baixo nível (mach, sysctl, IOKit, libproc). Só roda na fila do monitor.
private final class Sampler: @unchecked Sendable {
    private var previousTicks: [UInt32]?
    private var previousProcTimes: [pid_t: UInt64] = [:]
    private var previousProcDate: Date?
    private let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (UInt64(info.numer), UInt64(info.denom))
    }()

    func sample() -> SystemSample {
        var s = SystemSample()
        s.cpu = cpuUsage()
        readMemory(into: &s)
        readGPU(into: &s)
        return s
    }

    // MARK: CPU

    private func cpuUsage() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let ticks = [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3] // user, system, idle, nice
        defer { previousTicks = ticks }
        guard let prev = previousTicks else { return 0 }
        let d = zip(ticks, prev).map { Double($0 &- $1) }
        let total = d.reduce(0, +)
        return total > 0 ? (d[0] + d[1] + d[3]) / total : 0
    }

    // MARK: Memória

    private func readMemory(into s: inout SystemSample) {
        s.ramTotal = ProcessInfo.processInfo.physicalMemory
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            let page = UInt64(vm_kernel_page_size)
            // Mesma conta do Monitor de Atividade: memória de apps + residente + comprimida.
            let app = UInt64(stats.internal_page_count) &- UInt64(stats.purgeable_count)
            s.ramWired = UInt64(stats.wire_count) * page
            s.ramCompressed = UInt64(stats.compressor_page_count) * page
            s.ramUsed = app * page + s.ramWired + s.ramCompressed
            s.ramCached = (UInt64(stats.external_page_count) + UInt64(stats.purgeable_count)) * page
        }

        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 {
            s.swapUsed = swap.xsu_used
            s.swapTotal = swap.xsu_total
        }
        if let free = sysctlInt("kern.memorystatus_level") {
            s.pressure = Double(100 - min(max(free, 0), 100)) / 100
        }
        if let level = sysctlInt("kern.memorystatus_vm_pressure_level") {
            s.pressureLevel = MemoryPressureLevel(rawValue: level) ?? .normal
        }
    }

    private func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? Int(value) : nil
    }

    // MARK: GPU

    private func readGPU(into s: inout SystemSample) {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any],
                  let perf = dict["PerformanceStatistics"] as? [String: Any],
                  let util = perf["Device Utilization %"] as? NSNumber else { continue }
            s.gpu = max(s.gpu ?? 0, util.doubleValue / 100)
            if let mem = perf["In use system memory"] as? NSNumber { s.gpuMemory = mem.uint64Value }
        }
    }

    // MARK: Processos das CLIs

    /// Agrupa os processos por CLI. Executáveis com o nome da CLI contam direto; processos
    /// `node`/`bun` são identificados pelos argumentos (pacote da CLI no caminho do script).
    func llmProcesses() -> [ProcessUsage] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 32)
        let n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        let now = Date()
        let elapsed = previousProcDate.map { now.timeIntervalSince($0) } ?? 0
        var times: [pid_t: UInt64] = [:]
        var groups: [String: ProcessUsage] = [:]

        for pid in pids.prefix(Int(max(n, 0))) where pid > 0 {
            guard let cli = classify(pid) else { continue }
            var info = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { continue }
            let cpuNs = (info.pti_total_user + info.pti_total_system) * timebase.numer / timebase.denom
            times[pid] = cpuNs
            var g = groups[cli] ?? ProcessUsage(id: cli)
            g.count += 1
            g.memory += info.pti_resident_size
            if elapsed > 0, let prev = previousProcTimes[pid], cpuNs >= prev {
                g.cpu += Double(cpuNs - prev) / 1e9 / elapsed * 100
            }
            groups[cli] = g
        }
        previousProcTimes = times
        previousProcDate = now
        return groups.values.sorted { $0.memory > $1.memory }
    }

    private static let cliNames = ["claude", "codex", "gemini", "dk"]
    private static let scriptMarkers: [(String, String)] = [
        ("@anthropic-ai/claude-code", "claude"), ("@openai/codex", "codex"),
        ("@google/gemini-cli", "gemini"), ("ai-dk-cli", "dk"),
    ]

    private func classify(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let path = String(cString: buffer)
        let name = (path as NSString).lastPathComponent.lowercased()
        if Self.cliNames.contains(name) { return name }
        let lower = path.lowercased()
        let isScriptHost = name == "node" || name == "bun"
        // Binários instalados por link (ex.: /opt/homebrew/bin/claude → …/versions/x.y.z):
        // o caminho real não tem o nome da CLI, mas o argv[0] tem.
        let mayBeLinked = Self.cliNames.contains { $0 != "dk" && lower.contains($0) }
        guard isScriptHost || mayBeLinked else { return nil }
        let args = arguments(of: pid)
        let invoked = (args.split(separator: " ").first.map(String.init) ?? "")
        let invokedName = (invoked as NSString).lastPathComponent.lowercased()
        if Self.cliNames.contains(invokedName) { return invokedName }
        guard isScriptHost else { return nil }
        return Self.scriptMarkers.first { args.contains($0.0) }?.1
    }

    /// Linha de comando do processo (KERN_PROCARGS2), para reconhecer CLIs em Node.
    private func arguments(of pid: pid_t) -> String {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var data = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &data, &size, nil, 0) == 0 else { return "" }
        // Formato: argc (Int32), caminho do executável, argumentos separados por \0.
        let bytes = data.prefix(min(size, 4096)).dropFirst(4).map { $0 == 0 ? UInt8(ascii: " ") : $0 }
        return String(decoding: bytes, as: UTF8.self)
    }
}
