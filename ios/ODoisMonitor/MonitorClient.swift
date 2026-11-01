import Foundation

struct MonitorError: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
}

/// Fala com o oDois Monitor do Mac pela API v1 (HTTPS via túnel da Cloudflare).
struct MonitorClient {
    let pairing: PairingInfo

    private func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) -> URLRequest {
        var req = URLRequest(url: URL(string: pairing.url.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path)!, timeoutInterval: 30)
        req.httpMethod = method
        req.setValue("Bearer \(pairing.token)", forHTTPHeaderField: "Authorization")
        req.setValue("oDois-Monitor-iOS", forHTTPHeaderField: "User-Agent")
        if let body {
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return req
    }

    private func send(_ req: URLRequest) async throws -> Data {
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
            throw MonitorError(status: status, message: message ?? "O Mac respondeu \(status).")
        }
        return data
    }

    private func state(_ req: URLRequest) async throws -> MonitorState {
        try MonitorJSON.decoder.decode(MonitorState.self, from: try await send(req))
    }

    func hello() async throws { _ = try await send(request("/v1/hello")) }
    func state() async throws -> MonitorState { try await state(request("/v1/state")) }

    /// Estado ao vivo (SSE, ~2 s). Termina quando a conexão cai ou a tarefa é cancelada.
    func stream() -> AsyncThrowingStream<MonitorState, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var req = request("/v1/stream")
                    req.timeoutInterval = 3600
                    req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                    let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    guard status == 200 else { throw MonitorError(status: status, message: status == 401 ? "Aparelho não pareado ou revogado." : "O Mac respondeu \(status).") }
                    for try await line in bytes.lines where line.hasPrefix("data: ") {
                        if let data = line.dropFirst(6).data(using: .utf8),
                           let s = try? MonitorJSON.decoder.decode(MonitorState.self, from: data) {
                            continuation.yield(s)
                        }
                    }
                    continuation.finish(throwing: MonitorError(status: 0, message: "Conexão encerrada."))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func refresh() async throws { _ = try await send(request("/v1/refresh", method: "POST", body: [:])) }
    func startTask(_ id: Int) async throws -> MonitorState { try await state(request("/v1/tasks/\(id)/start", method: "POST", body: [:])) }
    func pauseTimer(_ id: Int) async throws -> MonitorState { try await state(request("/v1/timers/\(id)/pause", method: "POST", body: [:])) }
    func discardTimer(_ id: Int) async throws -> MonitorState { try await state(request("/v1/timers/\(id)/discard", method: "POST", body: ["confirm": true])) }
    func finishTimer(_ id: Int, hours: Double, date: String, activityType: Int, comment: String) async throws -> MonitorState {
        try await state(request("/v1/timers/\(id)/finish", method: "POST", body: ["hours": hours, "date": date, "activityType": activityType, "comment": comment]))
    }
    func markRead(_ id: Int) async throws -> MonitorState { try await state(request("/v1/notifications/\(id)/read", method: "POST", body: [:])) }
    func stopProcess(_ pid: Int32, force: Bool) async throws -> MonitorState {
        try await state(request("/v1/processes/\(pid)/stop", method: "POST", body: ["confirm": true, "force": force]))
    }
    func activityTypes(_ slug: String) async throws -> ActivityTypes {
        try JSONDecoder().decode(ActivityTypes.self, from: try await send(request("/v1/projects/\(slug)/activity-types")))
    }
    func image(_ path: String) async -> Data? { try? await send(request(path)) }
}
