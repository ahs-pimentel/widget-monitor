import Foundation
import Security

/// Pareamento guardado no Keychain (só neste aparelho, disponível após o primeiro desbloqueio,
/// para o refresh em segundo plano). O token nunca é exibido nem registrado em log.
enum Keychain {
    private static let service = "me.o2d.odoismonitor.pairing"
    private static let account = "mac"

    static func load() -> PairingInfo? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(PairingInfo.self, from: data)
    }

    static func save(_ info: PairingInfo) {
        guard let data = try? JSONEncoder().encode(info) else { return }
        clear()
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(attrs as CFDictionary, nil)
    }

    static func clear() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
    }
}
