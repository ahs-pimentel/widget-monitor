import Foundation

/// Último estado recebido, gravado no App Group para o widget (que não fala com a rede).
enum SharedState {
    static let group = "group.me.o2d.odoismonitor"
    private static let key = "lastState"
    private static let receivedKey = "lastStateReceivedAt"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: group) }

    static func save(_ state: MonitorState, receivedAt: Date = Date()) {
        guard let data = try? MonitorJSON.encoder.encode(state) else { return }
        defaults?.set(data, forKey: key)
        defaults?.set(receivedAt, forKey: receivedKey)
    }

    static func load() -> (state: MonitorState, receivedAt: Date)? {
        guard let data = defaults?.data(forKey: key),
              let state = try? MonitorJSON.decoder.decode(MonitorState.self, from: data) else { return nil }
        return (state, defaults?.object(forKey: receivedKey) as? Date ?? Date())
    }

    static func clear() {
        defaults?.removeObject(forKey: key)
        defaults?.removeObject(forKey: receivedKey)
    }
}
