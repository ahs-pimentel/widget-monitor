import AppKit
import UserNotifications

/// Um aviso a mostrar. `key` identifica o caso: o mesmo `key` não se repete dentro do `cooldown`.
struct Alert: Equatable {
    let key: String
    let title: String
    let body: String
    /// nil = avisa uma única vez por `key` (ex.: a janela do limite já entra no `key`).
    let cooldown: TimeInterval?
}

/// Regras dos alertas, sem efeitos colaterais: recebem o estado atual e devolvem os avisos.
enum AlertRules {
    /// Limites de uso (ex.: Codex): avisa nestes percentuais.
    static let limitThresholds: [Double] = [90, 100]
    /// Sessão disparando: tokens de uma sessão nos últimos 60 minutos. O padrão (150 M) fica
    /// acima do uso normal medido aqui (picos de 50 M a 110 M/h) e pega só o que foge da curva.
    static var sessionTokensPerHour: Int {
        let saved = UserDefaults.standard.integer(forKey: "alertSessionTokensPerHour")
        return saved > 0 ? saved : 150_000_000
    }

    static func evaluate(
        snapshots: [String: UsageSnapshot],
        names: [String: String],
        system: SystemSample?,
        processes: [ProcessUsage],
        now: Date = Date()
    ) -> [Alert] {
        var alerts: [Alert] = []

        for (id, snap) in snapshots {
            let name = names[id] ?? id
            for limit in snap.limits {
                // Do maior para o menor: em 100% não avisa também os 90%.
                guard let threshold = limitThresholds.sorted(by: >).first(where: { limit.usedPercent >= $0 }) else { continue }
                let window = limit.resetsAt.map { String(Int($0.timeIntervalSince1970)) } ?? "sem-reset"
                let reset = limit.resetsAt.map { "Reinicia \(Format.until($0, now: now)) (\(Format.time($0)))." } ?? ""
                alerts.append(Alert(
                    key: "limit:\(id):\(limit.label):\(window):\(Int(threshold))",
                    title: threshold >= 100 ? "\(name): \(limit.label.lowercased()) esgotado" : "\(name): \(limit.label.lowercased()) em \(Int(limit.usedPercent.rounded()))%",
                    body: reset,
                    cooldown: nil
                ))
            }
            for session in snap.sessions where session.lastHourTokens >= sessionTokensPerHour {
                let project = session.project ?? "Sessão \(session.id.prefix(6))"
                alerts.append(Alert(
                    key: "session:\(id):\(session.id)",
                    title: "\(name): sessão consumindo rápido",
                    body: "\(project) usou \(Format.tokens(session.lastHourTokens)) tokens na última hora"
                        + (session.model.map { " (\($0))" } ?? "") + ".",
                    cooldown: 3 * 3600
                ))
            }
        }

        if let system, system.pressureLevel == .critical {
            let heavy = processes.prefix(3).map { "\(names[$0.id] ?? $0.id) \(Bytes.format($0.memory))" }
            alerts.append(Alert(
                key: "memory:critical",
                title: "Pressão de memória crítica",
                body: "RAM \(Bytes.format(system.ramUsed)) de \(Bytes.format(system.ramTotal)) · swap \(Bytes.format(system.swapUsed))."
                    + (heavy.isEmpty ? "" : " CLIs: " + heavy.joined(separator: ", ") + "."),
                cooldown: 30 * 60
            ))
        }
        return alerts.sorted { $0.key < $1.key }
    }
}

/// Entrega os avisos como notificações do macOS, sem repetir o mesmo caso.
@MainActor
final class AlertCenter: NSObject, UNUserNotificationCenterDelegate {
    private enum Keys {
        static let enabled = "alertsEnabled"
        static let sent = "alertsSent"
    }

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: Keys.enabled) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Keys.enabled) }
    }

    /// Quando cada `key` foi avisado; persiste para não repetir após reiniciar o app.
    private var sent: [String: Date] {
        get { UserDefaults.standard.dictionary(forKey: Keys.sent) as? [String: Date] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: Keys.sent) }
    }

    /// Só existe dentro do .app (as notificações exigem bundle identifier).
    private let center: UNUserNotificationCenter? =
        Bundle.main.bundleIdentifier != nil ? UNUserNotificationCenter.current() : nil

    override init() {
        super.init()
        center?.delegate = self
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        // Esquece avisos com mais de 14 dias.
        sent = sent.filter { Date().timeIntervalSince($0.value) < 14 * 86_400 }
    }

    func handle(_ alerts: [Alert], now: Date = Date()) {
        guard enabled else { return }
        var record = sent
        for alert in alerts {
            if let last = record[alert.key] {
                guard let cooldown = alert.cooldown, now.timeIntervalSince(last) >= cooldown else { continue }
            }
            record[alert.key] = now
            deliver(alert)
        }
        if record != sent { sent = record }
    }

    func sendTest() {
        deliver(Alert(
            key: "test:\(UUID().uuidString)",
            title: "LLM Monitor",
            body: "Alerta de teste: as notificações estão funcionando.",
            cooldown: nil
        ))
    }

    private func deliver(_ alert: Alert) {
        guard let center else {
            print("ALERTA: \(alert.title) — \(alert.body)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        center.add(UNNotificationRequest(identifier: alert.key, content: content, trigger: nil))
    }

    /// O app não tem janela principal; mostra o banner mesmo com ele "em primeiro plano".
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
