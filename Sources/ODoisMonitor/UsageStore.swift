import AppKit
import Combine

/// Estado observável: CLIs detectadas e o último snapshot de cada uma.
@MainActor
final class UsageStore: ObservableObject {
    struct Item: Identifiable {
        let provider: UsageProvider
        let icon: NSImage?
        var id: String { provider.id }
    }

    @Published private(set) var items: [Item] = []
    @Published private(set) var snapshots: [String: UsageSnapshot] = [:]
    @Published private(set) var updatedAt: [String: Date] = [:]
    @Published private(set) var loading: Set<String> = []

    nonisolated static let allProviders: [UsageProvider] = [
        ClaudeProvider(), CodexProvider(), GeminiProvider(), AntigravityProvider(), DKProvider(), SeaProvider(), SystemProvider(),
    ]
    private let all = UsageStore.allProviders
    private let queue = DispatchQueue(label: "odois-monitor.load", qos: .utility)
    private var timer: Timer?

    init() {
        detect()
        refreshAll()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshAll() }
        }
    }

    /// Grava os caches dos leitores de log (ao fechar o app).
    func flush() {
        all.forEach { $0.flush() }
    }

    func detect() {
        items = all.filter(\.isInstalled).map { Item(provider: $0, icon: $0.appIcon) }
    }

    func refreshAll() {
        items.forEach { refresh($0.provider) }
    }

    /// Recarrega se o dado tiver mais de `maxAge` segundos (usado no hover).
    func refreshIfStale(_ id: String, maxAge: TimeInterval = 15) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        if let at = updatedAt[id], Date().timeIntervalSince(at) < maxAge { return }
        refresh(item.provider)
    }

    private func refresh(_ provider: UsageProvider) {
        let id = provider.id
        guard !loading.contains(id) else { return }
        loading.insert(id)
        queue.async { [provider] in
            let snap = provider.load()
            Task { @MainActor in
                self.snapshots[id] = snap
                self.updatedAt[id] = Date()
                self.loading.remove(id)
            }
        }
    }
}
