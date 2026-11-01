import SwiftUI
import WidgetKit

enum Connection { case unpaired, connecting, live, offline }

/// Estado do monitor para o app inteiro: stream ao vivo com reconexão e ações.
@MainActor
final class Repository: ObservableObject {
    static let shared = Repository()

    @Published private(set) var pairing: PairingInfo? = Keychain.load()
    @Published private(set) var connection: Connection = .unpaired
    @Published private(set) var state: MonitorState?
    @Published private(set) var receivedAt = Date()
    @Published private(set) var error: String?
    @Published var toast: String?

    private var liveTask: Task<Void, Never>?
    private var images: [String: UIImage?] = [:]

    var client: MonitorClient? { pairing.map(MonitorClient.init) }

    private init() {
        if pairing != nil {
            connection = .connecting
            if let cached = SharedState.load() { state = cached.state; receivedAt = cached.receivedAt }
        }
    }

    /// Pareia com o conteúdo do QR code e confere com `/v1/hello`.
    func pair(_ raw: String) async -> String? {
        guard let info = PairingInfo.parse(raw) else {
            return "Código inválido. Gere um novo em Acesso remoto → Parear celular… no Mac."
        }
        do {
            try await MonitorClient(pairing: info).hello()
            Keychain.save(info)
            #if DEBUG
            if ProcessInfo.processInfo.environment["ODOIS_SKIP_NOTIFICATIONS"] == nil { Alerts.requestPermission() }
            #else
            Alerts.requestPermission()
            #endif
            pairing = info
            connection = .connecting
            error = nil
            startLive()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func unpair() {
        stopLive()
        Keychain.clear()
        SharedState.clear()
        images = [:]
        pairing = nil
        state = nil
        connection = .unpaired
        LiveActivityController.end()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Liga o stream (app em primeiro plano). Reconecta com espera crescente.
    func startLive() {
        guard let client, liveTask == nil else { return }
        liveTask = Task { [weak self] in
            var backoff: UInt64 = 2
            while !Task.isCancelled {
                do {
                    if self?.state == nil { self?.apply(try await client.state()) }
                    for try await s in client.stream() {
                        backoff = 2
                        self?.apply(s)
                    }
                } catch let e as MonitorError where e.status == 401 {
                    self?.connection = .offline
                    self?.error = "Este iPhone foi desconectado no Mac. Pareie de novo."
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    self?.connection = .offline
                    self?.error = "Sem conexão com o Mac (\(error.localizedDescription))."
                }
                try? await Task.sleep(nanoseconds: backoff * 1_000_000_000)
                backoff = min(backoff * 2, 30)
                self?.connection = .connecting
            }
        }
    }

    func stopLive() {
        liveTask?.cancel()
        liveTask = nil
    }

    private var lastWidgetReload = Date.distantPast

    private func apply(_ s: MonitorState) {
        state = s
        receivedAt = Date()
        connection = .live
        error = nil
        SharedState.save(s, receivedAt: receivedAt)
        LiveActivityController.sync(s.sea?.running ?? s.sea?.timers.first, host: s.host ?? "Mac", receivedAt: receivedAt)
        // Widget: no máximo a cada 60 s (o iOS limita recarregamentos).
        if Date().timeIntervalSince(lastWidgetReload) > 60 {
            lastWidgetReload = Date()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Executa uma ação; o Mac devolve o estado novo. Falhas viram aviso.
    func act(_ success: String? = nil, _ block: @escaping (MonitorClient) async throws -> MonitorState?) {
        guard let client else { return }
        Task {
            do {
                if let s = try await block(client) { apply(s) }
                if let success { show(success) }
            } catch {
                show(error.localizedDescription)
            }
        }
    }

    func show(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if toast == text { toast = nil }
        }
    }

    func image(_ path: String) async -> UIImage? {
        if let cached = images[path] { return cached }
        let image = await client?.image(path).flatMap(UIImage.init(data:))
        images[path] = image
        return image
    }
}
