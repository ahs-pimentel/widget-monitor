import AppKit
import Combine

/// Liga e desliga o acesso remoto: servidor local (127.0.0.1) + túnel nomeado da Cloudflare.
/// O endereço público e o túnel vêm de `~/.config/odois-monitor/cloudflared.yml`.
@MainActor
final class RemoteAccess: ObservableObject {
    static let shared = RemoteAccess()
    static let port: UInt16 = 47862

    enum Status: Equatable {
        case off
        case starting
        case online
        case error(String)

        var label: String {
            switch self {
            case .off: return "Desligado"
            case .starting: return "Conectando…"
            case .online: return "Online"
            case .error(let m): return "Erro: \(m)"
            }
        }
    }

    @Published private(set) var status: Status = .off
    @Published private(set) var devices: [PairedDevice] = RemoteAuth.shared.list

    private let server = HTTPServer(port: RemoteAccess.port) { await RemoteHub.shared.handle($0) }
    private var tunnel: Process?
    private var restartWork: DispatchWorkItem?
    private static let enabledKey = "remoteAccessEnabled"

    var enabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    static let configURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/odois-monitor/cloudflared.yml")

    /// Endereço público lido do `hostname:` da config do túnel.
    var publicURL: URL? {
        guard let text = try? String(contentsOf: Self.configURL, encoding: .utf8),
              let line = text.split(separator: "\n").first(where: { $0.contains("hostname:") }) else { return nil }
        let host = line.split(separator: ":", maxSplits: 1).last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return host.isEmpty ? nil : URL(string: "https://\(host)")
    }

    /// Ao abrir o app: volta ao estado em que estava.
    func restore() {
        if enabled { start() }
    }

    func toggle() {
        enabled ? stop() : start()
    }

    func start() {
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        status = .starting
        do {
            try server.start()
        } catch {
            status = .error("porta \(Self.port) ocupada")
            return
        }
        launchTunnel()
    }

    func stop() {
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        restartWork?.cancel()
        tunnel?.terminationHandler = nil
        tunnel?.terminate()
        tunnel = nil
        server.stop()
        status = .off
    }

    /// Ao fechar o app, derruba o túnel junto (sem mudar a preferência).
    func shutdown() {
        tunnel?.terminationHandler = nil
        tunnel?.terminate()
        server.stop()
    }

    // MARK: - Pareamento

    func pair(name: String) -> (device: PairedDevice, token: String) {
        let result = RemoteAuth.shared.pair(name: name)
        devices = RemoteAuth.shared.list
        return result
    }

    func revoke(_ id: String) {
        RemoteAuth.shared.revoke(id)
        devices = RemoteAuth.shared.list
    }

    func reloadDevices() { devices = RemoteAuth.shared.list }

    // MARK: - Túnel

    private func launchTunnel() {
        guard FileManager.default.fileExists(atPath: Self.configURL.path) else {
            status = .error("config do túnel ausente")
            return
        }
        guard let binary = BinaryLocator.find("cloudflared") else {
            status = .error("cloudflared não encontrado")
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["--no-autoupdate", "--config", Self.configURL.path, "tunnel", "run"]
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe
        // "Registered tunnel connection" no log indica que a borda da Cloudflare aceitou o túnel.
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let text = String(decoding: handle.availableData, as: UTF8.self)
            if text.contains("Registered tunnel connection") {
                Task { @MainActor in RemoteAccess.shared.status = .online }
            }
        }
        process.terminationHandler = { _ in
            pipe.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in RemoteAccess.shared.tunnelExited() }
        }
        do {
            try process.run()
            tunnel = process
        } catch {
            status = .error("não iniciou o cloudflared")
        }
    }

    /// O túnel caiu (rede, suspensão): tenta de novo em 10 s enquanto estiver ligado.
    private func tunnelExited() {
        tunnel = nil
        guard enabled else { return }
        status = .starting
        let work = DispatchWorkItem { Task { @MainActor in
            if RemoteAccess.shared.enabled, RemoteAccess.shared.tunnel == nil { RemoteAccess.shared.launchTunnel() }
        } }
        restartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: work)
    }
}
