import AppKit
import SwiftUI

if let i = CommandLine.arguments.firstIndex(of: "--snapshot") {
    let path = CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] : "build/snapshots"
    MainActor.assumeIsolated { Snapshots.render(to: URL(fileURLWithPath: path)) }
    exit(0)
}

// `LLMMonitor --bench` mede a leitura dos logs: a primeira carga e uma recarga
// (que relê só os arquivos alterados desde a anterior).
if CommandLine.arguments.contains("--bench") {
    for p in UsageStore.allProviders where p.id != SystemProvider.identifier {
        var times: [Double] = []
        for _ in 0..<3 {
            let start = DispatchTime.now()
            _ = p.load()
            times.append(Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e6)
        }
        print(String(format: "%-12@ primeira %.0f ms · recargas %.1f ms / %.1f ms", p.name as NSString, times[0], times[1], times[2]))
        p.flush()
    }
    exit(0)
}

// `LLMMonitor --dump` imprime o consumo lido dos logs e sai (útil para conferir os números).
if CommandLine.arguments.contains("--dump") {
    for p in UsageStore.allProviders where p.id != SystemProvider.identifier {
        print("== \(p.name)  instalado=\(p.isInstalled)  binário=\(BinaryLocator.find(p.binary) ?? "-")")
        guard p.isInstalled else { continue }
        let s = p.load()
        print("  hoje: total=\(s.today.total) in=\(s.today.input) out=\(s.today.output) cacheR=\(s.today.cacheRead) cacheW=\(s.today.cacheWrite)")
        print("  respostas=\(s.messagesToday) sessões=\(s.sessionsToday) modelo=\(s.topModel ?? "-") última=\(s.lastActivity.map { Format.relative($0) } ?? "-")")
        print("  7 dias=\(s.week.total) por dia=\(s.daily.map(Format.tokens))")
        for l in s.limits { print("  \(l.label): \(l.usedPercent)% reset=\(l.resetsAt.map { Format.until($0) } ?? "-")") }
        if let b = s.blockTokens, let e = s.blockEndsAt { print("  bloco 5h: \(Format.tokens(b)) termina \(Format.time(e))") }
        if let plan = s.plan { print("  plano: \(plan)") }
        if let c = s.costWeek { print("  custo: hoje \(Format.usd(s.costToday ?? 0)) · 7 dias \(Format.usd(c)) \(s.source ?? "")") }
        for x in s.sessions.prefix(3) {
            print("  sessão \(x.project ?? "?") \(x.model ?? "-") \(Format.tokens(x.tokens.total)) \(x.messages) resp. \(Format.relative(x.last))\(x.cost > 0 ? " " + Format.usd(x.cost) : "")")
        }
        if let note = s.note { print("  nota: \(note)") }
    }
    // Uma leitura do sistema (CPU precisa de duas amostras para a variação).
    MainActor.assumeIsolated {
        let m = SystemMonitor.shared
        RunLoop.main.run(until: Date().addingTimeInterval(2.5))
        let s = m.current
        print("== Sistema  CPU \(Int(s.cpu * 100))%  RAM \(Bytes.format(s.ramUsed))/\(Bytes.format(s.ramTotal))  GPU \(s.gpu.map { "\(Int($0 * 100))%" } ?? "-")")
        print("  pressão \(s.pressureLevel.label) \(Int(s.pressure * 100))%  comprimida \(Bytes.format(s.ramCompressed))  swap \(Bytes.format(s.swapUsed))/\(Bytes.format(s.swapTotal))")
        for p in m.processes { print("  proc \(p.id): \(p.count) proc. \(Int(p.cpu))% CPU \(Bytes.format(p.memory))") }
    }
    // Tamanho que o card ocuparia para cada CLI (confere a medição usada no hover).
    MainActor.assumeIsolated {
        let store = UsageStore()
        let selection = CardSelection()
        // Espera os snapshots chegarem para medir o card já preenchido.
        let deadline = Date().addingTimeInterval(10)
        while store.snapshots.count < store.items.count, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        let host = NSHostingController(rootView: UsageCardView(store: store, selection: selection))
        for item in store.items {
            selection.id = item.id
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            let size = host.sizeThatFits(in: CGSize(width: UsageCardView.width + BarMetrics.inset * 2, height: 2000))
            print("card \(item.id): \(Int(size.width))x\(Int(size.height))")
        }
    }
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // Sem ícone no Dock nem barra de menus: só a barra flutuante.
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
