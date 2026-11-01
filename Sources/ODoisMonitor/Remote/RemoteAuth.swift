import CryptoKit
import Foundation
import Security

/// Aparelho pareado. No disco fica só o hash do token (SHA-256), nunca o token.
struct PairedDevice: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    let tokenHash: String
    let createdAt: Date
    var lastSeenAt: Date?
}

/// Pareamento e verificação dos tokens dos aparelhos, com limite de tentativas.
/// Arquivo: `~/.config/odois-monitor/devices.json` (permissão 0600).
final class RemoteAuth: @unchecked Sendable {
    static let shared = RemoteAuth()

    private let lock = NSLock()
    private var devices: [PairedDevice] = []
    private var failures: [String: [Date]] = [:]
    private let file = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/odois-monitor/devices.json")

    /// Até 10 tentativas inválidas por origem a cada 5 minutos.
    static let maxFailures = 10
    static let failureWindow: TimeInterval = 300

    private var loadedAt: Date?

    private init() {
        reloadIfChanged()
    }

    /// Relê o arquivo se outro processo o alterou (ex.: pareamento pelo binário de teste).
    /// Chamar com o lock tomado ou na inicialização.
    private func reloadIfChanged() {
        let modified = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
        guard modified != loadedAt else { return }
        loadedAt = modified
        if let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder.iso.decode([PairedDevice].self, from: data) {
            devices = saved
        } else {
            devices = []
        }
    }

    var list: [PairedDevice] {
        lock.lock(); defer { lock.unlock() }
        return devices
    }

    /// Cria um aparelho e devolve o token em claro uma única vez (vai no QR code).
    func pair(name: String) -> (device: PairedDevice, token: String) {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let token = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let device = PairedDevice(id: UUID().uuidString, name: name, tokenHash: Self.hash(token), createdAt: Date())
        lock.lock()
        devices.append(device)
        save()
        lock.unlock()
        return (device, token)
    }

    func revoke(_ id: String) {
        lock.lock()
        devices.removeAll { $0.id == id }
        save()
        lock.unlock()
    }

    func rename(_ id: String, to name: String) {
        lock.lock()
        if let i = devices.firstIndex(where: { $0.id == id }) { devices[i].name = name }
        save()
        lock.unlock()
    }

    enum Verdict { case ok(PairedDevice), denied, rateLimited }

    /// Confere `Authorization: Bearer <token>` em tempo constante e conta falhas por origem.
    func verify(_ request: HTTPRequest) -> Verdict {
        let origin = request.headers["cf-connecting-ip"] ?? "local"
        let now = Date()
        lock.lock(); defer { lock.unlock() }
        reloadIfChanged()
        let recent = (failures[origin] ?? []).filter { now.timeIntervalSince($0) < Self.failureWindow }
        failures[origin] = recent
        guard recent.count < Self.maxFailures else { return .rateLimited }

        let header = request.headers["authorization"] ?? ""
        let token = header.hasPrefix("Bearer ") ? String(header.dropFirst(7)) : ""
        let candidate = Self.hash(token)
        var match: Int?
        for (i, d) in devices.enumerated() where Self.constantTimeEqual(d.tokenHash, candidate) { match = i }
        guard !token.isEmpty, let i = match else {
            failures[origin, default: []].append(now)
            return .denied
        }
        // Registra o último acesso no máximo uma vez por minuto (evita gravar a cada 2 s).
        if devices[i].lastSeenAt.map({ now.timeIntervalSince($0) > 60 }) ?? true {
            devices[i].lastSeenAt = now
            save()
        }
        return .ok(devices[i])
    }

    // MARK: - Apoio

    private func save() {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder.iso.encode(devices) else { return }
        try? data.write(to: file, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        loadedAt = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
    }

    static func hash(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<x.count { diff |= x[i] ^ y[i] }
        return diff == 0
    }
}

extension JSONDecoder {
    static let iso: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

extension JSONEncoder {
    static let iso: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}
