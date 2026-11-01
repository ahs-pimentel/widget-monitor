import BackgroundTasks
import UserNotifications
import WidgetKit

/// Em segundo plano (quando o iOS libera): busca o estado do Mac, avisa o que é novo
/// e atualiza o widget. As regras são as mesmas do Mac e do Android.
enum BackgroundRefresh {
    static let identifier = "me.o2d.odoismonitor.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            handle(task as! BGAppRefreshTask)
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        schedule()
        let work = Task {
            guard let pairing = Keychain.load(), let state = try? await MonitorClient(pairing: pairing).state() else {
                task.setTaskCompleted(success: false)
                return
            }
            SharedState.save(state)
            WidgetCenter.shared.reloadAllTimelines()
            await Alerts.notify(state)
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }
}

enum Alerts {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Cada caso avisa uma vez; na primeira execução só registra o que já existe.
    static func notify(_ state: MonitorState) async {
        let defaults = UserDefaults.standard
        var sent = Set(defaults.stringArray(forKey: "alertsSent") ?? [])
        let first = !defaults.bool(forKey: "alertsSeeded")
        let host = state.host ?? "Mac"
        var pending: [(String, String, String)] = []

        func post(_ key: String, _ title: String, _ body: String) {
            guard sent.insert(key).inserted, !first else { return }
            pending.append((key, title, body))
        }

        for p in state.providers {
            for l in p.limits {
                let window = l.resetsAt.map { "\(Int($0.timeIntervalSince1970))" } ?? "-"
                if l.usedPercent >= 100 {
                    post("limit:\(p.id):\(l.label):\(window):100", "\(p.name): \(l.label.lowercased()) esgotado", "No Mac \(host).")
                } else if l.usedPercent >= 90 {
                    post("limit:\(p.id):\(l.label):\(window):90", "\(p.name): \(l.label.lowercased()) em \(Int(l.usedPercent))%", "No Mac \(host).")
                } else if let eta = l.forecastAt, eta.timeIntervalSinceNow < 3600, eta.timeIntervalSinceNow > 0 {
                    post("forecast:\(p.id):\(l.label):\(window)", "\(p.name): \(l.label.lowercased()) deve esgotar \(Fmt.until(eta))",
                         "Está em \(Int(l.usedPercent))% e subindo, no Mac \(host).")
                }
            }
        }
        if state.system.pressureLevel == "critical" {
            post("memory:\(Int(Date().timeIntervalSince1970 / 1800))", "Pressão de memória crítica", "O Mac \(host) está sem memória livre.")
        }
        for n in state.sea?.notifications ?? [] {
            post("sea:\(n.id)", n.title, n.body ?? "")
        }

        defaults.set(Array(sent.suffix(400)), forKey: "alertsSent")
        defaults.set(true, forKey: "alertsSeeded")
        for (key, title, body) in pending {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: key, content: content, trigger: nil))
        }
    }
}
