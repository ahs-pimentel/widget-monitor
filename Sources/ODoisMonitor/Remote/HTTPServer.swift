import Foundation
import Network

/// Requisição HTTP/1.1 já lida (cabeçalhos em minúsculas).
struct HTTPRequest {
    let method: String
    let path: String
    let query: [String: String]
    let headers: [String: String]
    let body: Data

    func json() -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
    }
}

/// Resposta simples ou um stream de eventos (SSE) que fica aberto.
enum HTTPResponse {
    case data(status: Int, contentType: String, body: Data)
    /// Mantém a conexão aberta; o `start` recebe um "send" para empurrar eventos e
    /// devolve um cancelamento chamado quando o cliente desconecta.
    case stream(start: (_ send: @escaping (String) -> Bool) -> (() -> Void))

    static func json(_ object: Any, status: Int = 200) -> HTTPResponse {
        let body = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        return .data(status: status, contentType: "application/json; charset=utf-8", body: body)
    }

    static func encodable<T: Encodable>(_ value: T, status: Int = 200) -> HTTPResponse {
        .data(status: status, contentType: "application/json; charset=utf-8", body: (try? RemoteJSON.encoder.encode(value)) ?? Data("{}".utf8))
    }

    static func error(_ status: Int, _ code: String, _ message: String) -> HTTPResponse {
        json(["error": ["code": code, "message": message]], status: status)
    }
}

enum RemoteJSON {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()
}

/// Servidor HTTP/1.1 mínimo sobre Network.framework, só em 127.0.0.1 (quem chega de
/// fora é o túnel da Cloudflare). Uma requisição por conexão, corpo até 64 KB.
final class HTTPServer: @unchecked Sendable {
    typealias Handler = @Sendable (HTTPRequest) async -> HTTPResponse

    let port: UInt16
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "odois-monitor.http")
    private let handler: Handler
    private static let maxBody = 64 * 1024

    init(port: UInt16, handler: @escaping Handler) {
        self.port = port
        self.handler = handler
    }

    var isRunning: Bool { listener != nil }

    func start() throws {
        guard listener == nil else { return }
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port)!)
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params)
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Conexão

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = Self.parse(buffer) {
                self.respond(connection, request)
            } else if error != nil || complete || buffer.count > Self.maxBody + 16_384 {
                connection.cancel()
            } else {
                self.receive(connection, buffer: buffer)
            }
        }
    }

    private func respond(_ connection: NWConnection, _ request: HTTPRequest) {
        let handler = handler
        Task {
            let response = await handler(request)
            switch response {
            case let .data(status, contentType, body):
                var head = "HTTP/1.1 \(status) \(Self.reason(status))\r\n"
                head += "Content-Type: \(contentType)\r\nContent-Length: \(body.count)\r\n"
                head += "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
            case let .stream(start):
                let head = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-store\r\n"
                    + "X-Accel-Buffering: no\r\nConnection: keep-alive\r\n\r\n"
                connection.send(content: Data(head.utf8), completion: .contentProcessed { _ in })
                var open = true
                let cancel = start { chunk in
                    guard open else { return false }
                    connection.send(content: Data(chunk.utf8), completion: .contentProcessed { error in
                        if error != nil { open = false }
                    })
                    return open
                }
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .failed, .cancelled: open = false; cancel()
                    default: break
                    }
                }
            }
        }
    }

    // MARK: - Parser

    private static func parse(_ data: Data) -> HTTPRequest? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: data[..<headerEnd.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }
        let first = lines.removeFirst().split(separator: " ")
        guard first.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = min(Int(headers["content-length"] ?? "0") ?? 0, maxBody)
        let bodyStart = headerEnd.upperBound
        guard data.count - bodyStart >= length else { return nil }
        let body = data[bodyStart..<(bodyStart + length)]

        let target = String(first[1])
        let components = URLComponents(string: target)
        var query: [String: String] = [:]
        components?.queryItems?.forEach { query[$0.name] = $0.value ?? "" }
        return HTTPRequest(
            method: String(first[0]).uppercased(),
            path: components?.path ?? target,
            query: query,
            headers: headers,
            body: Data(body)
        )
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 201: return "Created"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 409: return "Conflict"
        case 422: return "Unprocessable Entity"
        case 429: return "Too Many Requests"
        default: return status < 400 ? "OK" : "Error"
        }
    }
}
