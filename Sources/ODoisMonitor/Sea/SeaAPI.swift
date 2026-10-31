import Foundation

/// Chamadas diretas à API do Dashboard para o que a CLI `sea` não cobre
/// (hoje: o ranking completo, que pede `user_id`).
///
/// Usa a mesma credencial da CLI, na mesma ordem de precedência dela
/// (`SEA_DASHBOARD_TOKEN`/`SEA_DASHBOARD_URL`, depois `~/.config/sea/credentials`).
/// O token só existe em memória durante a chamada: nunca é exibido, registrado ou gravado.
enum SeaAPI {
    struct Credential {
        let url: URL
        let token: String
    }

    /// Lê a credencial do perfil ativo. YAML simples gravado pela CLI:
    /// `default_profile: x` e `profiles: { x: { url: ..., token: ... } }`.
    static func credential() -> Credential? {
        let env = ProcessInfo.processInfo.environment
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/sea/credentials")
        let yaml = (try? String(contentsOf: path, encoding: .utf8)) ?? ""
        let file = parse(yaml)
        let profile = env["SEA_DASHBOARD_PROFILE"] ?? file.defaultProfile ?? "default"
        let entry = file.profiles[profile] ?? [:]
        guard let token = env["SEA_DASHBOARD_TOKEN"] ?? entry["token"], !token.isEmpty,
              let url = URL(string: (env["SEA_DASHBOARD_URL"] ?? entry["url"] ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        else { return nil }
        return Credential(url: url, token: token)
    }

    /// GET autenticado; devolve o JSON de nível superior.
    static func get(_ path: String, query: [String: String] = [:]) throws -> [String: Any] {
        guard let cred = credential() else { throw SeaError.failed("Credencial da sea não encontrada (rode sea auth login).") }
        var components = URLComponents(url: cred.url.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = components?.url else { throw SeaError.unexpected(path) }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Bearer \(cred.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("oDois-Monitor", forHTTPHeaderField: "User-Agent")

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<(Data, Int), Error> = .failure(SeaError.unexpected(path))
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error { result = .failure(error) } else {
                result = .success((data ?? Data(), (response as? HTTPURLResponse)?.statusCode ?? 0))
            }
            semaphore.signal()
        }.resume()
        semaphore.wait()

        let (data, status) = try result.get()
        guard (200..<300).contains(status) else { throw SeaError.failed("Dashboard respondeu \(status) em \(path).") }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw SeaError.unexpected(path) }
        return obj
    }

    /// Ranking completo da pessoa: manual + automático + medalhas, como na página do ranking.
    static func ranking(user: Int) throws -> SeaRanking? {
        let body = try get("api/v1/ops/ranking_summary", query: ["user_id": "\(user)"])
        guard let data = body["data"] as? [String: Any] else { return nil }
        func number(_ key: String) -> Double? { (data[key] as? NSNumber)?.doubleValue }
        guard let total = number("total_score") else { return nil }
        return SeaRanking(
            year: data["year"] as? Int ?? Calendar.current.component(.year, from: Date()),
            score: total,
            manual: number("manual_total") ?? 0,
            automatic: number("auto_total") ?? 0,
            badges: number("badge_score") ?? 0,
            // Só vêm para quem tem papel de líder/gestor.
            position: data["position"] as? Int,
            total: (data["total_ranked"] as? Int) ?? (data["total"] as? Int)
        )
    }

    // MARK: - YAML mínimo

    private struct File {
        var defaultProfile: String?
        var profiles: [String: [String: String]] = [:]
    }

    /// Só o necessário do arquivo da CLI: chaves por indentação, valores escalares.
    private static func parse(_ yaml: String) -> File {
        var file = File()
        var inProfiles = false
        var current: String?
        for raw in yaml.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(raw)
            guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("#") else { continue }
            let indent = line.prefix { $0 == " " }.count
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<colon]).trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            var value = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let f = value.first, f == "\"" || f == "'", value.last == f {
                value = String(value.dropFirst().dropLast())
            }
            if indent == 0 {
                inProfiles = key == "profiles"
                current = nil
                if key == "default_profile", !value.isEmpty { file.defaultProfile = value }
            } else if inProfiles, value.isEmpty {
                // "  nome-do-perfil:" abre um perfil.
                current = key
                if file.profiles[key] == nil { file.profiles[key] = [:] }
            } else if inProfiles, let current, !value.isEmpty {
                file.profiles[current]?[key] = value
            }
        }
        return file
    }
}
