import AppKit
import Combine

/// Cronômetro de uma tarefa. Só um roda por vez; os pausados guardam o tempo acumulado.
struct TaskTimer: Codable, Equatable {
    let task: SeaTask
    let startedAt: Date
    var accumulated: TimeInterval = 0
    var runningSince: Date?

    var isRunning: Bool { runningSince != nil }

    func elapsed(now: Date = Date()) -> TimeInterval {
        accumulated + (runningSince.map { now.timeIntervalSince($0) } ?? 0)
    }
}

/// Tarefas do Sea Dashboard e os cronômetros. Os cronômetros ficam no app (funcionam sem
/// rede e sobrevivem a fechar o app); só o "Finalizar" escreve no Dashboard.
@MainActor
final class SeaStore: ObservableObject {
    static let shared = SeaStore()

    @Published private(set) var tasks: [SeaTask] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var updatedAt: Date?
    @Published private(set) var timers: [Int: TaskTimer] = [:]
    /// Tarefas com uma escrita em andamento no Dashboard.
    @Published private(set) var busy: Set<Int> = []
    /// Última confirmação ("1,25 h registradas em #710"), some depois de alguns segundos.
    @Published private(set) var message: String?

    /// Notificações não lidas do Dashboard.
    @Published private(set) var notifications: [SeaNotification] = []
    /// Dispara com as notificações que chegaram desde a última busca (o notch abre com elas).
    let incoming = PassthroughSubject<[SeaNotification], Never>()
    /// Ids já vistos; na primeira busca as existentes só entram aqui (não abrem o notch).
    private var seen: Set<Int>? = (UserDefaults.standard.array(forKey: "seaSeenNotifications") as? [Int]).map(Set.init)
    private var notifyTimer: Timer?
    private var fetchingNotifications = false

    let client = SeaClient.shared
    private var userId: Int?
    /// Endereço do Dashboard informado pela credencial.
    @Published private(set) var baseURL: URL?
    /// Conta logada na `sea` (nome · e-mail).
    @Published private(set) var account: String?
    /// Posição no ranking anual (nil se a pessoa não aparece ou sem permissão).
    @Published private(set) var ranking: SeaRanking?
    /// Projetos recolhidos no card (por slug), salvos entre aberturas.
    @Published private(set) var collapsed: Set<String> =
        Set(UserDefaults.standard.stringArray(forKey: "seaCollapsedProjects") ?? [])
    private var refreshTimer: Timer?
    private let queue = DispatchQueue(label: "odois-monitor.sea", qos: .userInitiated)
    private static let timersKey = "seaTimers"

    var isAvailable: Bool { client.isInstalled }
    var running: TaskTimer? { timers.values.first(where: \.isRunning) }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.timersKey),
           let saved = try? JSONDecoder().decode([Int: TaskTimer].self, from: data) {
            timers = saved
        }
        guard isAvailable else { return }
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        fetchNotifications()
        notifyTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.fetchNotifications() }
        }
    }

    // MARK: - Notificações

    func fetchNotifications() {
        guard isAvailable, !fetchingNotifications else { return }
        fetchingNotifications = true
        let client = client
        queue.async {
            let list = try? client.unreadNotifications()
            Task { @MainActor in
                self.fetchingNotifications = false
                guard let list else { return }
                self.notifications = list
                let ids = Set(list.map(\.id))
                if let seen = self.seen {
                    let fresh = list.filter { !seen.contains($0.id) }
                    if !fresh.isEmpty { self.incoming.send(fresh) }
                    self.seen = seen.union(ids)
                } else {
                    self.seen = ids
                }
                let keep = Array(self.seen ?? []).sorted().suffix(500)
                UserDefaults.standard.set(Array(keep), forKey: "seaSeenNotifications")
            }
        }
    }

    /// Abre a página da notificação e a marca como lida.
    func open(_ n: SeaNotification) {
        if let base = baseURL, let url = n.url(base: base) {
            NSWorkspace.shared.open(url)
        }
        markRead(n)
    }

    func markRead(_ n: SeaNotification) {
        notifications.removeAll { $0.id == n.id }
        let client = client
        queue.async { try? client.markRead(n.id) }
    }

    // MARK: - Lista

    func refresh() {
        guard isAvailable, !loading else { return }
        loading = true
        let client = client, known = userId, knownBase = baseURL, knownAccount = account
        queue.async {
            do {
                let me = try known.map { ($0, knownBase, knownAccount) } ?? client.whoami()
                let user = me.0
                var all: [SeaTask] = []
                for project in try client.projects(user: user) {
                    all += (try? client.openTasks(project: project.slug, name: project.name, user: user)) ?? []
                }
                let ranking = try? SeaAPI.ranking(user: user)
                let sorted = all.sorted { ($0.isInProgress ? 0 : 1, $0.projectName, $0.number) < ($1.isInProgress ? 0 : 1, $1.projectName, $1.number) }
                Task { @MainActor in
                    self.userId = user
                    if let ranking { self.ranking = ranking }
                    self.baseURL = me.1 ?? self.baseURL
                    self.account = me.2 ?? self.account
                    self.tasks = sorted
                    self.error = nil
                    self.updatedAt = Date()
                    self.loading = false
                }
            } catch {
                Task { @MainActor in
                    self.error = error.localizedDescription
                    self.loading = false
                }
            }
        }
    }

    func toggleCollapsed(_ slug: String) {
        if collapsed.contains(slug) { collapsed.remove(slug) } else { collapsed.insert(slug) }
        UserDefaults.standard.set(Array(collapsed), forKey: "seaCollapsedProjects")
    }

    /// Abre a tarefa no navegador padrão.
    func open(_ task: SeaTask) {
        guard let base = baseURL else { return }
        NSWorkspace.shared.open(task.url(base: base))
    }

    // MARK: - Cronômetro

    /// Inicia (ou retoma) a tarefa e pausa a que estiver rodando. Uma tarefa "não iniciada"
    /// passa a "em andamento" no Dashboard.
    func start(_ task: SeaTask) {
        let now = Date()
        for (id, t) in timers where t.isRunning && id != task.id {
            timers[id]?.accumulated = t.elapsed(now: now)
            timers[id]?.runningSince = nil
        }
        var timer = timers[task.id] ?? TaskTimer(task: task, startedAt: now)
        if timer.runningSince == nil { timer.runningSince = now }
        timers[task.id] = timer
        save()

        if task.statusId == SeaTask.notStarted {
            write(task.id) { client in try client.transition(task, to: SeaTask.inProgress) } done: { [weak self] in
                self?.refresh()
            }
        }
    }

    func pause(_ id: Int) {
        guard let t = timers[id], t.isRunning else { return }
        timers[id]?.accumulated = t.elapsed()
        timers[id]?.runningSince = nil
        save()
    }

    func toggle(_ task: SeaTask) {
        timers[task.id]?.isRunning == true ? pause(task.id) : start(task)
    }

    func discard(_ id: Int) {
        guard let t = timers[id] else { return }
        let alert = NSAlert()
        alert.messageText = "Descartar o cronômetro de \(t.task.title)?"
        alert.informativeText = "\(Self.clock(t.elapsed())) não serão registrados no Dashboard."
        alert.addButton(withTitle: "Descartar")
        alert.addButton(withTitle: "Cancelar")
        guard alert.runAboveMonitor() == .alertFirstButtonReturn else { return }
        timers[id] = nil
        save()
    }

    /// Pausa, pede confirmação (horas, data, atividade, comentário) e grava no Dashboard.
    func finish(_ id: Int) {
        guard let t = timers[id] else { return }
        pause(id)
        guard t.elapsed() >= 60 else {
            show("Menos de 1 minuto: nada a registrar.")
            return
        }
        busy.insert(id)
        let client = client, slug = t.task.projectSlug
        queue.async {
            let types = (try? client.activityTypes(project: slug)) ?? []
            Task { @MainActor in
                self.busy.remove(id)
                self.confirmAndLog(id, types: types)
            }
        }
    }

    private func confirmAndLog(_ id: Int, types: [SeaActivityType]) {
        guard let t = timers[id], let user = userId else { return }
        guard !types.isEmpty else {
            show("Não consegui ler os tipos de atividade de \(t.task.projectName).")
            return
        }
        let form = FinishForm(timer: t, types: types, preferred: Self.preferredActivity(t.task.projectSlug))
        guard let result = form.run() else { return }
        UserDefaults.standard.set(result.activityType, forKey: "seaActivity.\(t.task.projectSlug)")

        write(id) { client in
            _ = try client.logTime(
                task: t.task, user: user, date: result.date, hours: result.hours,
                activityType: result.activityType, comment: result.comment
            )
        } done: { [weak self] in
            self?.timers[id] = nil
            self?.save()
            self?.show("\(Format.hours(result.hours)) registradas em \(t.task.title)")
        }
    }

    // MARK: - Apoio

    /// Escrita no Dashboard fora da main thread; em caso de erro mostra um alerta.
    private func write(_ id: Int, _ body: @escaping @Sendable (SeaClient) throws -> Void, done: @escaping @MainActor () -> Void) {
        busy.insert(id)
        let client = client
        queue.async {
            let failure: String?
            do { try body(client); failure = nil } catch { failure = error.localizedDescription }
            Task { @MainActor in
                self.busy.remove(id)
                if let failure {
                    let alert = NSAlert()
                    alert.messageText = "O Dashboard recusou a operação"
                    alert.informativeText = failure
                    alert.runAboveMonitor()
                } else {
                    done()
                }
            }
        }
    }

    private func show(_ text: String) {
        message = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            if self?.message == text { self?.message = nil }
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(timers) {
            UserDefaults.standard.set(data, forKey: Self.timersKey)
        }
    }

    private static func preferredActivity(_ slug: String) -> Int? {
        let saved = UserDefaults.standard.integer(forKey: "seaActivity.\(slug)")
        return saved > 0 ? saved : nil
    }

    /// 3725 s → "1:02:05"; abaixo de 1 h → "2:05".
    static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}

extension Format {
    /// 1.25 → "1,25 h".
    static func hours(_ h: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return (f.string(from: NSNumber(value: h)) ?? String(format: "%.2f", h)) + " h"
    }
}

// MARK: - Ações sem interface (acesso remoto pelo celular)

extension SeaStore {
    /// Descarta sem perguntar (a confirmação foi feita no celular).
    func discardNow(_ id: Int) {
        timers[id] = nil
        save()
    }

    /// Tipos de atividade do projeto (o celular monta o formulário de finalizar).
    func activityTypes(project slug: String) async -> [SeaActivityType] {
        let client = client
        return await withCheckedContinuation { cont in
            queue.async { cont.resume(returning: (try? client.activityTypes(project: slug)) ?? []) }
        }
    }

    /// Grava as horas do cronômetro no Dashboard sem abrir o formulário do Mac.
    /// Devolve nil em caso de sucesso ou a mensagem de erro do Dashboard.
    func logRemotely(_ id: Int, hours: Double, date: Date, activityType: Int, comment: String) async -> String? {
        guard let t = timers[id] else { return "Cronômetro não encontrado." }
        guard let user = userId else { return "Usuário do Dashboard ainda não carregado." }
        guard hours > 0, hours <= 24 else { return "Horas devem ficar entre 0 e 24." }
        pause(id)
        busy.insert(id)
        let client = client
        let failure: String? = await withCheckedContinuation { cont in
            queue.async {
                do {
                    _ = try client.logTime(task: t.task, user: user, date: date, hours: hours, activityType: activityType, comment: comment)
                    cont.resume(returning: nil)
                } catch {
                    cont.resume(returning: error.localizedDescription)
                }
            }
        }
        busy.remove(id)
        if failure == nil {
            UserDefaults.standard.set(activityType, forKey: "seaActivity.\(t.task.projectSlug)")
            timers[id] = nil
            save()
            show("\(Format.hours(hours)) registradas em \(t.task.title) (pelo celular)")
        }
        return failure
    }

    /// Tipo de atividade lembrado para o projeto (padrão do formulário no celular).
    func preferredActivityType(_ slug: String) -> Int? {
        let saved = UserDefaults.standard.integer(forKey: "seaActivity.\(slug)")
        return saved > 0 ? saved : nil
    }
}
