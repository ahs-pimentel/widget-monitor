import Foundation

/// Conta logada em cada CLI, lida dos arquivos de configuração locais.
/// Só extrai identificação (e-mail, organização, perfil); nenhum token é exibido ou guardado.
enum Accounts {
    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    private static func json(_ path: String) -> [String: Any]? {
        guard let data = try? Data(contentsOf: home.appendingPathComponent(path)) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Claude Code: `~/.claude.json` → `oauthAccount.emailAddress`.
    static func claude() -> String? {
        (json(".claude.json")?["oauthAccount"] as? [String: Any])?["emailAddress"] as? String
    }

    /// Codex: e-mail das claims públicas do `id_token` (a parte do meio do JWT).
    static func codex() -> String? {
        guard let tokens = json(".codex/auth.json")?["tokens"] as? [String: Any],
              let idToken = tokens["id_token"] as? String else {
            return json(".codex/auth.json")?["OPENAI_API_KEY"] != nil ? "Chave de API" : nil
        }
        let parts = idToken.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return claims["email"] as? String
    }

    /// Gemini CLI: `~/.gemini/google_accounts.json` → `active`.
    static func gemini() -> String? {
        json(".gemini/google_accounts.json")?["active"] as? String
    }

    /// DK: perfil ativo de `~/.dk/settings.json` (nome · provedor).
    static func dk() -> String? {
        guard let settings = json(".dk/settings.json"),
              let active = settings["activeProfileId"] as? String,
              let profiles = settings["profiles"] as? [[String: Any]],
              let profile = profiles.first(where: { $0["id"] as? String == active }) else { return nil }
        let name = profile["name"] as? String
        let provider = profile["provider"] as? String
        return [name, provider].compactMap { $0 }.joined(separator: " · ")
    }
}
