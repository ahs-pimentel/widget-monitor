import Foundation

/// Uma tarefa do Sea Dashboard atribuída ao usuário logado.
struct SeaTask: Identifiable, Equatable, Codable, Hashable {
    /// Id interno (o que o lançamento de horas pede).
    let id: Int
    /// Número visível no projeto (#710).
    let number: Int
    let subject: String
    let statusId: Int
    let projectSlug: String
    let projectName: String

    static let notStarted = 2
    static let inProgress = 3

    var isInProgress: Bool { statusId == Self.inProgress }
    var title: String { "#\(number) \(subject.trimmingCharacters(in: .whitespaces))" }

    /// Página da tarefa no Dashboard: `<base>/timesheet/projects/<slug>/tasks/<número>`.
    func url(base: URL) -> URL {
        base.appendingPathComponent("timesheet/projects/\(projectSlug)/tasks/\(number)")
    }
}

struct SeaActivityType: Equatable {
    let id: Int
    let label: String
}

enum SeaError: LocalizedError {
    case notInstalled
    case failed(String)
    case unexpected(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled: return "CLI sea não encontrada."
        case .failed(let message): return message
        case .unexpected(let what): return "Resposta inesperada do sea (\(what))."
        }
    }
}

/// Fala com o Sea Dashboard pela CLI `sea`, com a credencial que a pessoa já tem.
/// Nunca lê nem mostra o token. Chamadas bloqueantes: use fora da main thread.
final class SeaClient: Sendable {
    static let shared = SeaClient()

    let executable: String? = BinaryLocator.find("sea") ?? {
        let bundled = "/Applications/SEA Dock.app/Contents/Resources/sea-cli/bin/sea"
        return FileManager.default.isExecutableFile(atPath: bundled) ? bundled : nil
    }()

    var isInstalled: Bool { executable != nil }

    // MARK: - Leitura

    /// Usuário logado e o endereço do Dashboard da credencial (para montar links).
    func whoami() throws -> (id: Int, base: URL?) {
        let data = try json(["auth", "whoami", "--json"])
        guard let id = (data["data"] as? [String: Any])?["id"] as? Int else { throw SeaError.unexpected("whoami") }
        return (id, (data["url"] as? String).flatMap(URL.init(string:)))
    }

    /// Projetos em que a pessoa está alocada de 30 dias atrás a 30 dias à frente.
    func projects(user: Int, now: Date = Date()) throws -> [(slug: String, name: String)] {
        let cal = Calendar.current
        let from = cal.date(byAdding: .day, value: -30, to: now) ?? now
        let to = cal.date(byAdding: .day, value: 30, to: now) ?? now
        let data = try json(["ops", "allocation-map", "--start-date=\(Self.day(from))", "--end-date=\(Self.day(to))", "--json"])
        let allocations = ((data["data"] as? [String: Any])?["allocations"] as? [String: Any])?["\(user)"] as? [[String: Any]] ?? []
        var seen = Set<String>()
        return allocations.compactMap { a in
            guard let slug = a["project_slug"] as? String, seen.insert(slug).inserted else { return nil }
            return (slug, a["project_name"] as? String ?? slug)
        }
    }

    /// Tarefas da pessoa em "não iniciado" ou "em andamento" num projeto.
    func openTasks(project slug: String, name: String, user: Int) throws -> [SeaTask] {
        let data = try json(["task", "list", "-p", slug, "--assignee", "\(user)", "--open", "--limit", "100", "--json"])
        let rows = data["data"] as? [[String: Any]] ?? []
        return rows.compactMap { row in
            guard let id = row["id"] as? Int, let number = row["task_number"] as? Int,
                  let status = (row["status"] as? [String: Any])?["id"] as? Int,
                  status == SeaTask.notStarted || status == SeaTask.inProgress else { return nil }
            return SeaTask(
                id: id, number: number, subject: row["subject"] as? String ?? "Sem título",
                statusId: status, projectSlug: slug, projectName: name
            )
        }
    }

    func activityTypes(project slug: String) throws -> [SeaActivityType] {
        let data = try json(["activity-type", "list", "-p", slug, "--json"])
        return (data["data"] as? [[String: Any]] ?? []).compactMap { row in
            guard let id = row["id"] as? Int, let label = row["label"] as? String else { return nil }
            return SeaActivityType(id: id, label: label)
        }
    }

    // MARK: - Escrita

    func transition(_ task: SeaTask, to status: Int) throws {
        _ = try run(["task", "transition", "\(task.number)", "\(status)", "-p", task.projectSlug])
    }

    /// Grava as horas na folha da pessoa que cobre a data (cria a folha da semana se faltar).
    /// Devolve o id da entrada criada.
    func logTime(
        task: SeaTask, user: Int, date: Date, hours: Double, activityType: Int, comment: String
    ) throws -> Int {
        let sheet = try timesheet(project: task.projectSlug, user: user, covering: date)
        var args = [
            "timesheet", "entry", "add", "-p", task.projectSlug, "-t", "\(sheet)",
            "--task=\(task.id)", "--date=\(Self.day(date))",
            "--hours=\(String(format: "%.2f", hours))", "--activity-type=\(activityType)", "--json",
        ]
        if !comment.isEmpty { args.append("--comment=\(comment)") }
        let data = try json(args)
        guard let id = (data["data"] as? [String: Any])?["id"] as? Int else { throw SeaError.unexpected("entry add") }
        return id
    }

    /// Folha de horas da pessoa no projeto cuja semana contém a data.
    private func timesheet(project slug: String, user: Int, covering date: Date) throws -> Int {
        let cal = Calendar.current
        let from = cal.date(byAdding: .day, value: -6, to: date) ?? date
        let to = cal.date(byAdding: .day, value: 6, to: date) ?? date
        let data = try json([
            "timesheet", "list", "-p", slug, "--user", "\(user)",
            "--from", Self.day(from), "--to", Self.day(to), "--json",
        ])
        let target = Self.day(date)
        for row in data["data"] as? [[String: Any]] ?? [] {
            // Confere o dono: lançar na folha de outra pessoa é aceito em silêncio pela API.
            guard let id = row["id"] as? Int,
                  (row["user"] as? [String: Any])?["id"] as? Int == user,
                  let start = row["period_start"] as? String, let end = row["period_end"] as? String,
                  start <= target, target <= end else { continue }
            return id
        }
        // Nenhuma cobre a data: cria a da semana (segunda a domingo).
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = .current
        let monday = iso.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        let sunday = iso.date(byAdding: .day, value: 6, to: monday) ?? date
        let created = try json([
            "timesheet", "create", "-p", slug,
            "--period-start=\(Self.day(monday))", "--period-end=\(Self.day(sunday))", "--json",
        ])
        guard let id = (created["data"] as? [String: Any])?["id"] as? Int else { throw SeaError.unexpected("timesheet create") }
        return id
    }

    // MARK: - Processo

    private func json(_ args: [String]) throws -> [String: Any] {
        let out = try run(args)
        guard let obj = try JSONSerialization.jsonObject(with: out) as? [String: Any] else {
            throw SeaError.unexpected(args.prefix(2).joined(separator: " "))
        }
        return obj
    }

    private func run(_ args: [String]) throws -> Data {
        guard let executable else { throw SeaError.notInstalled }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        var env = ProcessInfo.processInfo.environment
        // Apps abertos pelo Finder vêm sem locale; a sea quebra ao ler UTF-8 em US-ASCII.
        env["LANG"] = "en_US.UTF-8"
        env["LC_ALL"] = "en_US.UTF-8"
        env["PATH"] = (env["PATH"].map { $0 + ":" } ?? "") + "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
        process.environment = env
        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let out = stdout.fileHandleForReading.readDataToEndOfFile()
        let err = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: err.isEmpty ? out : err, as: UTF8.self)
                .split(separator: "\n").first.map(String.init) ?? "sea saiu com código \(process.terminationStatus)"
            throw SeaError.failed(message)
        }
        return out
    }

    static func day(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
