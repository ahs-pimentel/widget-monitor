import AppKit

/// Item "Tarefas" da barra: tarefas do Sea Dashboard com cronômetro. Não lê logs de
/// consumo; o card usa o SeaStore. Aparece quando a CLI `sea` está configurada.
final class SeaProvider: UsageProvider, @unchecked Sendable {
    static let identifier = "sea"
    let id = SeaProvider.identifier
    let name = "Tarefas Sea"
    let symbol = "timer"
    let tint = NSColor(red: 0.05, green: 0.55, blue: 0.75, alpha: 1)
    let binary = "sea"
    let appBundleNames: [String] = []
    /// A pasta de credenciais indica que a pessoa já fez `sea auth login`.
    var dataDirectory: URL { home.appendingPathComponent(".config/sea") }

    func load() -> UsageSnapshot { .empty }
}
