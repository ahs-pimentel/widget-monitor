import AppKit
import Collaboration

/// Acesso remoto: monta o estado do monitor para o celular e executa as ações pedidas.
/// Toda rota (menos `/v1/health`) exige o token de um aparelho pareado.
@MainActor
final class RemoteHub {
    static let shared = RemoteHub()
    weak var store: UsageStore?

    // MARK: - Roteamento

    nonisolated func handle(_ req: HTTPRequest) async -> HTTPResponse {
        if req.method == "GET", req.path == "/v1/health" {
            return .json(["ok": true, "app": "oDois Monitor", "api": 1])
        }
        switch RemoteAuth.shared.verify(req) {
        case .rateLimited: return .error(429, "rate_limited", "Muitas tentativas inválidas. Aguarde alguns minutos.")
        case .denied: return .error(401, "unauthorized", "Aparelho não pareado ou token revogado.")
        case .ok(let device): return await route(req, device: device)
        }
    }

    private func route(_ req: HTTPRequest, device: PairedDevice) async -> HTTPResponse {
        guard req.path.hasPrefix("/v1/") else { return .error(404, "not_found", "Rota inexistente.") }
        let sea = SeaStore.shared

        if match(req, "GET", "hello") != nil {
            return .json(["device": device.name, "host": Host.current().localizedName ?? "Mac", "api": 1])
        }

        if match(req, "GET", "state") != nil {
            return .encodable(state())
        }

        if match(req, "GET", "stream") != nil {
            return .stream { send in
                let timer = DispatchSource.makeTimerSource(queue: .main)
                timer.schedule(deadline: .now(), repeating: 2)
                timer.setEventHandler {
                    MainActor.assumeIsolated {
                        guard let data = try? RemoteJSON.encoder.encode(RemoteHub.shared.state()) else { return }
                        if !send("event: state\ndata: \(String(decoding: data, as: UTF8.self))\n\n") { timer.cancel() }
                    }
                }
                timer.resume()
                return { timer.cancel() }
            }
        }

        if let args = match(req, "GET", "icons/*") {
            let file = args[0]
            guard file.hasSuffix(".png") else { return .error(404, "not_found", "Rota inexistente.") }
            let id = String(file.dropLast(4))
            guard let image = store?.items.first(where: { $0.id == id })?.icon, let png = image.png(size: 128) else {
                return .error(404, "not_found", "Ícone indisponível.")
            }
            return .data(status: 200, contentType: "image/png", body: png)
        }

        if match(req, "GET", "avatar.png") != nil {
            guard let image = CBUserIdentity(posixUID: getuid(), authority: .default())?.image,
                  let png = image.png(size: 256) else { return .error(404, "not_found", "Sem foto.") }
            return .data(status: 200, contentType: "image/png", body: png)
        }

        if match(req, "POST", "refresh") != nil {
            store?.refreshAll()
            sea.refresh()
            sea.fetchNotifications()
            return .json(["ok": true])
        }


        // MARK: Tarefas e cronômetros

        if let args = match(req, "POST", "tasks/*/start") {
            let id = args[0]
            guard let task = sea.tasks.first(where: { "\($0.id)" == id }) ?? sea.timers[Int(id) ?? -1]?.task else {
                return .error(404, "not_found", "Tarefa não encontrada.")
            }
            sea.start(task)
            return .encodable(state())
        }

        if let args = match(req, "POST", "timers/*/pause") {
            let id = args[0]
            guard let key = Int(id), sea.timers[key] != nil else { return .error(404, "not_found", "Cronômetro não encontrado.") }
            sea.pause(key)
            return .encodable(state())
        }

        if let args = match(req, "POST", "timers/*/discard") {
            let id = args[0]
            guard let key = Int(id), sea.timers[key] != nil else { return .error(404, "not_found", "Cronômetro não encontrado.") }
            guard req.json()["confirm"] as? Bool == true else { return .error(422, "confirmation_required", "Envie confirm: true.") }
            sea.discardNow(key)
            return .encodable(state())
        }

        if let args = match(req, "POST", "timers/*/finish") {
            let id = args[0]
            guard let key = Int(id), sea.timers[key] != nil else { return .error(404, "not_found", "Cronômetro não encontrado.") }
            let body = req.json()
            guard let hours = (body["hours"] as? NSNumber)?.doubleValue,
                  let activity = (body["activityType"] as? NSNumber)?.intValue else {
                return .error(422, "invalid", "Informe hours e activityType.")
            }
            let date = (body["date"] as? String).flatMap(Self.day) ?? Date()
            let comment = (body["comment"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let failure = await sea.logRemotely(key, hours: hours, date: date, activityType: activity, comment: comment) {
                return .error(422, "dashboard_refused", failure)
            }
            return .encodable(state())
        }

        if let args = match(req, "GET", "projects/*/activity-types") {
            let slug = args[0]
            let types = await sea.activityTypes(project: slug)
            return .json(["data": types.map { ["id": $0.id, "label": $0.label] }, "preferred": sea.preferredActivityType(slug) as Any])
        }

        if let args = match(req, "POST", "notifications/*/read") {
            let id = args[0]
            guard let n = sea.notifications.first(where: { "\($0.id)" == id }) else { return .error(404, "not_found", "Notificação não encontrada.") }
            sea.markRead(n)
            return .encodable(state())
        }


        // MARK: Processos

        if let args = match(req, "POST", "processes/*/stop") {
            let pid = args[0]
            let body = req.json()
            guard body["confirm"] as? Bool == true else { return .error(422, "confirmation_required", "Envie confirm: true.") }
            guard let value = Int32(pid), SystemMonitor.shared.cliProcesses.contains(where: { $0.pid == value }) else {
                return .error(404, "not_found", "Processo não é uma CLI monitorada.")
            }
            let ok = SystemMonitor.shared.stop(value, force: body["force"] as? Bool == true)
            return ok ? .encodable(state()) : .error(409, "stop_refused", "O processo mudou ou não aceitou o sinal.")
        }
        return .error(404, "not_found", "Rota inexistente.")
    }

    /// Casa método e caminho (sem o prefixo /v1/) com um padrão em que `*` é um segmento livre;
    /// devolve os segmentos livres, na ordem.
    private func match(_ req: HTTPRequest, _ method: String, _ pattern: String) -> [String]? {
        guard req.method == method else { return nil }
        let path = req.path.split(separator: "/").dropFirst().map(String.init)
        let expected = pattern.split(separator: "/").map(String.init)
        guard path.count == expected.count else { return nil }
        var args: [String] = []
        for (got, want) in zip(path, expected) {
            if want == "*" { args.append(got) } else if got != want { return nil }
        }
        return args
    }

    // MARK: - Estado

    func state() -> RemoteState {
        let items = store?.items ?? []
        let monitor = SystemMonitor.shared
        let names = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.provider.name) })
        let providers = items.filter { $0.id != SystemProvider.identifier && $0.id != SeaProvider.identifier }.map { item -> RemoteProvider in
            let snap = store?.snapshots[item.id] ?? .empty
            return RemoteProvider(
                id: item.id, name: item.provider.name, tint: item.provider.tint.hex, symbol: item.provider.symbol,
                monogram: item.provider.monogram, hasIcon: item.icon != nil,
                account: snap.account, plan: snap.plan, source: snap.source,
                active: Activity.isActive(snap.lastActivity), lastActivity: snap.lastActivity,
                today: RemoteTokens(snap.today), messagesToday: snap.messagesToday, sessionsToday: snap.sessionsToday,
                topModel: snap.topModel, weekTotal: snap.week.total, daily: snap.daily,
                costToday: snap.costToday, costWeek: snap.costWeek,
                limits: snap.limits.map { RemoteLimit(label: $0.label, usedPercent: $0.usedPercent, resetsAt: $0.resetsAt) },
                block: snap.blockTokens.flatMap { t in snap.blockEndsAt.map { RemoteBlock(tokens: t, endsAt: $0) } },
                sessions: snap.sessions.prefix(5).map {
                    RemoteSession(id: $0.id, project: Format.project($0.project), model: $0.model, tokens: $0.tokens.total,
                                  messages: $0.messages, cost: $0.cost, last: $0.last, active: Activity.isActive($0.last))
                },
                note: snap.note
            )
        }
        let s = monitor.current
        let system = RemoteSystem(
            cpu: s.cpu, ramUsed: s.ramUsed, ramTotal: s.ramTotal, swapUsed: s.swapUsed, swapTotal: s.swapTotal,
            pressure: s.pressure, pressureLevel: "\(s.pressureLevel)", gpu: s.gpu,
            cpuHistory: monitor.history.map(\.cpu), pressureHistory: monitor.history.map(\.pressure)
        )
        let processes = monitor.cliProcesses.map {
            RemoteProcess(pid: $0.pid, cli: $0.cli, cliName: names[$0.cli] ?? $0.cli, project: $0.project, directory: $0.directory,
                          cpu: $0.cpu, memory: $0.memory, startedAt: $0.started, background: $0.background,
                          stopping: monitor.stopping[$0.pid] != nil)
        }
        let active = items.reduce(0) { sum, item in
            sum + (store?.snapshots[item.id]?.sessions.filter { Activity.isActive($0.last) }.count ?? 0)
        }
        return RemoteState(
            appVersion: AppInfo.versionLabel, generatedAt: Date(), host: Host.current().localizedName ?? "Mac",
            providers: providers, system: system, processes: processes, sea: seaState(), activeSessions: active
        )
    }

    private func seaState() -> RemoteSea? {
        let sea = SeaStore.shared
        guard sea.isAvailable else { return nil }
        func task(_ t: SeaTask) -> RemoteTask {
            RemoteTask(id: t.id, number: t.number, subject: t.subject.trimmingCharacters(in: .whitespaces), statusId: t.statusId,
                       inProgress: t.isInProgress, projectSlug: t.projectSlug, projectName: t.projectName,
                       url: sea.baseURL.map { t.url(base: $0).absoluteString }, busy: sea.busy.contains(t.id))
        }
        let now = Date()
        return RemoteSea(
            account: sea.account, dashboardURL: sea.baseURL?.absoluteString, loading: sea.loading, error: sea.error,
            updatedAt: sea.updatedAt,
            tasks: sea.tasks.map(task),
            timers: sea.timers.values.sorted { $0.startedAt < $1.startedAt }.map {
                RemoteTimer(task: task($0.task), startedAt: $0.startedAt, accumulated: $0.accumulated, runningSince: $0.runningSince,
                            running: $0.isRunning, elapsed: $0.elapsed(now: now),
                            preferredActivityType: sea.preferredActivityType($0.task.projectSlug))
            },
            notifications: sea.notifications.map { n in
                RemoteNotification(id: n.id, title: n.title, body: n.body, actor: n.actor,
                                   url: sea.baseURL.flatMap { n.url(base: $0)?.absoluteString }, createdAt: n.createdAt)
            },
            ranking: sea.ranking.map {
                RemoteRanking(year: $0.year, score: $0.score, manual: $0.manual, automatic: $0.automatic,
                              badges: $0.badges, position: $0.position, total: $0.total)
            },
            message: sea.message
        )
    }

    private static func day(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }
}
