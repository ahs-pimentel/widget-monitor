import AppKit

/// Item "Sistema" da barra: CPU, RAM, pressão de memória e GPU. Não lê logs; o card
/// usa o SystemMonitor. Existe como provider para ganhar ícone, hover e aba como as CLIs.
final class SystemProvider: UsageProvider, @unchecked Sendable {
    static let identifier = "system"
    let id = SystemProvider.identifier
    let name = "Sistema"
    let symbol = "cpu"
    let tint = NSColor(white: 0.45, alpha: 1)
    let binary = ""
    let appBundleNames: [String] = []
    var dataDirectory: URL { home }

    func load() -> UsageSnapshot { .empty }
}
