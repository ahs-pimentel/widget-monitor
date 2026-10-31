import Foundation

/// Interpreta as linhas de um arquivo de log. Uma instância por arquivo: pode guardar
/// estado entre linhas (ex.: o acumulado de tokens do Codex). É Codable para o estado
/// sobreviver no cache em disco entre aberturas do app.
protocol LineParser: AnyObject, Codable {
    func consume(_ line: Data) -> [UsageEvent]
}

/// Leitor de logs JSONL que só crescem (Claude Code, Codex). Guarda até onde cada arquivo
/// já foi lido e, a cada recarga, processa só as linhas novas, em paralelo. Se um arquivo
/// for truncado ou substituído, ele é relido do começo.
///
/// O progresso fica num cache em `~/Library/Caches`: ao abrir o app, só o que mudou desde
/// a última vez é lido. Importa quando os logs estão num disco lento (ex.: ~/.claude num
/// volume externo, onde ler tudo leva dezenas de segundos).
final class IncrementalLog<Parser: LineParser>: @unchecked Sendable {
    final class FileState: Codable {
        let inode: UInt64
        fileprivate(set) var offset: UInt64 = 0
        fileprivate(set) var events: [UsageEvent] = []
        let parser: Parser

        init(inode: UInt64, parser: Parser) {
            self.inode = inode
            self.parser = parser
        }
    }

    /// Mude quando o formato salvo ou a interpretação dos logs mudar: o cache antigo é descartado.
    private static var cacheVersion: Int { 1 }
    /// Intervalo mínimo entre gravações do cache enquanto o app roda.
    private static var saveInterval: TimeInterval { 120 }

    private var states: [String: FileState] = [:]
    private let lock = NSLock()
    private let makeParser: (URL) -> Parser
    private let cacheURL: URL?
    private var lastSave = Date.distantPast
    private var dirty = false

    init(name: String, makeParser: @escaping (URL) -> Parser) {
        self.makeParser = makeParser
        cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("br.com.seatecnologia.llmmonitor", isDirectory: true)
            .appendingPathComponent("\(name)-v\(Self.cacheVersion).plist")
        loadCache()
    }

    /// Lê o que há de novo nos arquivos e devolve o estado de cada um, na mesma ordem.
    func update(_ files: [URL]) -> [FileState] {
        lock.lock()
        defer { lock.unlock() }
        let list: [(URL, FileState)] = files.map { url in
            let inode = Self.inode(of: url)
            if let state = states[url.path], state.inode == inode, Self.size(of: url) >= state.offset {
                return (url, state)
            }
            let state = FileState(inode: inode, parser: makeParser(url))
            states[url.path] = state
            return (url, state)
        }
        // Esquece arquivos que saíram da janela de dias.
        let keep = Set(files.map(\.path))
        if states.count != keep.count { dirty = true }
        states = states.filter { keep.contains($0.key) }

        // Cada arquivo é avançado por uma única thread, então o estado dele não é compartilhado.
        var advanced = [Bool](repeating: false, count: list.count)
        advanced.withUnsafeMutableBufferPointer { flags in
            DispatchQueue.concurrentPerform(iterations: list.count) { i in
                flags[i] = Self.advance(list[i].0, list[i].1)
            }
        }
        if advanced.contains(true) { dirty = true }
        if dirty, Date().timeIntervalSince(lastSave) > Self.saveInterval { saveCache() }
        return list.map(\.1)
    }

    /// Grava o cache agora, se houver novidade (ex.: ao fechar o app).
    func flush() {
        lock.lock()
        defer { lock.unlock() }
        if dirty { saveCache() }
    }

    /// Avança um arquivo até o fim; devolve se leu algo novo.
    private static func advance(_ url: URL, _ state: FileState) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size > state.offset else { return false }
        try? handle.seek(toOffset: state.offset)
        guard let data = try? handle.readToEnd(),
              let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else { return false }
        // Só linhas completas; uma linha ainda sendo escrita fica para a próxima leitura.
        let complete = data[data.startIndex...lastNewline]
        var lineStart = complete.startIndex
        while lineStart < complete.endIndex {
            let lineEnd = JSONBytes.index(of: UInt8(ascii: "\n"), in: complete, from: lineStart) ?? complete.endIndex
            if lineEnd > lineStart {
                state.events += state.parser.consume(complete[lineStart..<lineEnd])
            }
            lineStart = lineEnd + 1
        }
        state.offset += UInt64(complete.count)
        return true
    }

    // MARK: Cache em disco (chamar com `lock` adquirido, exceto no init)

    private func loadCache() {
        guard let cacheURL, let data = try? Data(contentsOf: cacheURL),
              let saved = try? PropertyListDecoder().decode([String: FileState].self, from: data) else { return }
        states = saved
        lastSave = Date()
    }

    private func saveCache() {
        guard let cacheURL else { return }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let data = try? encoder.encode(states) else { return }
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cacheURL, options: .atomic)
        lastSave = Date()
        dirty = false
    }

    private static func inode(of url: URL) -> UInt64 {
        var st = stat()
        return stat(url.path, &st) == 0 ? UInt64(st.st_ino) : 0
    }

    private static func size(of url: URL) -> UInt64 {
        var st = stat()
        return stat(url.path, &st) == 0 ? UInt64(st.st_size) : 0
    }
}

/// Leitura direta de campos em bytes de JSON compacto, sem parsear a linha inteira.
///
/// Os padrões incluem as aspas e os dois-pontos (ex.: `"usage":{`). Dentro de uma string
/// JSON as aspas aparecem escapadas (`\"usage\":{`), então o padrão só casa com a chave
/// real da estrutura, nunca com texto citado dentro de conteúdo.
enum JSONBytes {
    static func pattern(_ s: String) -> Data { Data(s.utf8) }

    static func contains(_ line: Data, _ pattern: Data) -> Bool {
        find(pattern, in: line) != nil
    }

    /// Índice logo após a primeira ocorrência de `pattern` (memmem: bem mais rápido
    /// que Data.range(of:) em linhas de vários MB).
    static func find(_ pattern: Data, in line: Data) -> Data.Index? {
        let offset: Int? = line.withUnsafeBytes { hay in
            pattern.withUnsafeBytes { needle in
                guard let h = hay.baseAddress, let n = needle.baseAddress,
                      let hit = memmem(h, hay.count, n, needle.count) else { return nil }
                return h.distance(to: UnsafeRawPointer(hit)) + needle.count
            }
        }
        return offset.map { line.startIndex + $0 }
    }

    /// Posição do próximo byte `byte` a partir de `from` (memchr).
    static func index(of byte: UInt8, in data: Data, from: Data.Index) -> Data.Index? {
        let start = from - data.startIndex
        let offset: Int? = data.withUnsafeBytes { buf in
            guard let base = buf.baseAddress, start < buf.count,
                  let hit = memchr(base + start, Int32(byte), buf.count - start) else { return nil }
            return base.distance(to: UnsafeRawPointer(hit))
        }
        return offset.map { data.startIndex + $0 }
    }

    /// Valor de string logo após `pattern` (que termina em `":"`).
    static func string(in line: Data, after pattern: Data) -> String? {
        guard let after = find(pattern, in: line) else { return nil }
        var bytes: [UInt8] = []
        var i = after
        while i < line.endIndex {
            let b = line[i]
            if b == UInt8(ascii: "\\"), line.index(after: i) < line.endIndex {
                bytes.append(line[line.index(after: i)])
                i = line.index(i, offsetBy: 2)
                continue
            }
            if b == UInt8(ascii: "\"") { return String(decoding: bytes, as: UTF8.self) }
            bytes.append(b)
            i = line.index(after: i)
        }
        return nil
    }

    /// Objeto JSON que começa no `{` final de `pattern` (ex.: `"usage":{`).
    static func object(in line: Data, after pattern: Data) -> [String: Any]? {
        guard let after = find(pattern, in: line) else { return nil }
        let start = line.index(before: after)
        var depth = 0
        var inString = false
        var i = start
        while i < line.endIndex {
            let b = line[i]
            if inString {
                if b == UInt8(ascii: "\\") {
                    i = line.index(i, offsetBy: 2, limitedBy: line.endIndex) ?? line.endIndex
                    continue
                }
                if b == UInt8(ascii: "\"") { inString = false }
            } else if b == UInt8(ascii: "\"") {
                inString = true
            } else if b == UInt8(ascii: "{") {
                depth += 1
            } else if b == UInt8(ascii: "}") {
                depth -= 1
                if depth == 0 {
                    return try? JSONSerialization.jsonObject(with: line[start...i]) as? [String: Any]
                }
            }
            i = line.index(after: i)
        }
        return nil
    }
}

/// Converte "2026-10-31T00:57:19.224Z" sem formatter (rápido e sem trava entre threads).
/// Formatos diferentes caem no ISO8601DateFormatter.
enum FastISO {
    static func parse(_ s: String?) -> Date? {
        guard let s else { return nil }
        let b = Array(s.utf8)
        guard b.count >= 20, b[4] == 45, b[7] == 45, b[10] == 84, b[13] == 58, b[16] == 58,
              b.last == 90 else { return ISODate.parse(s) }
        func num(_ from: Int, _ len: Int) -> Int32? {
            var v: Int32 = 0
            for i in from..<(from + len) {
                guard b[i] >= 48, b[i] <= 57 else { return nil }
                v = v * 10 + Int32(b[i] - 48)
            }
            return v
        }
        guard let y = num(0, 4), let mo = num(5, 2), let d = num(8, 2),
              let h = num(11, 2), let mi = num(14, 2), let se = num(17, 2) else { return ISODate.parse(s) }
        var t = tm()
        t.tm_year = y - 1900
        t.tm_mon = mo - 1
        t.tm_mday = d
        t.tm_hour = h
        t.tm_min = mi
        t.tm_sec = se
        var fraction = 0.0
        if b[19] == 46 {
            var scale = 0.1
            for c in b[20..<(b.count - 1)] where c >= 48 && c <= 57 {
                fraction += Double(c - 48) * scale
                scale /= 10
            }
        }
        return Date(timeIntervalSince1970: Double(timegm(&t)) + fraction)
    }
}
