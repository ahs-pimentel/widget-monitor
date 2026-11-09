import SwiftUI

/// Processos das CLIs um a um, com PID, projeto e um botão para parar.
/// Parar pede dois cliques (o primeiro arma, o segundo envia SIGTERM); se o processo
/// não sair em 3 s, o botão passa a "Forçar" (SIGKILL).
struct ProcessListView: View {
    @ObservedObject var monitor: SystemMonitor
    let names: [String: String]

    /// PID armado pelo primeiro clique; desarma sozinho depois de alguns segundos.
    @State private var armed: pid_t?

    var body: some View {
        let list = monitor.cliProcesses
        let background = list.filter(\.background).count
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(
                "Processos das CLIs",
                detail: list.isEmpty ? nil : "\(list.count) · \(background) em 2º plano"
            )
            if list.isEmpty {
                Text("Nenhuma CLI de LLM rodando agora.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if list.count > Self.visibleRows {
                // Com dezenas de processos o card passava da altura da janela e quebrava o notch.
                ScrollView(.vertical) { rows(list) }
                    .frame(height: Self.scrollHeight)
            } else {
                rows(list)
            }
        }
    }

    static let visibleRows = 6
    static let scrollHeight: CGFloat = 230

    private func rows(_ list: [CLIProcess]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(list) { p in
                row(p)
                if p.id != list.last?.id { Divider().opacity(0.4) }
            }
        }
    }

    private func row(_ p: CLIProcess) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(p.project ?? names[p.cli] ?? p.cli)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1).truncationMode(.middle)
                    if p.background {
                        Text("2º plano")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 4).padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.orange.opacity(0.25)))
                            .foregroundStyle(.orange)
                            .fixedSize()
                    }
                    Spacer(minLength: 4)
                    Text(Bytes.format(p.memory))
                        .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                        .fixedSize()
                }
                Text(detail(p))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 4)
            stopButton(p)
        }
        .padding(.vertical, 2)
        .help([
            "PID \(p.pid) (pai \(p.parent))",
            p.directory,
            p.background ? "Sem terminal: aberto por um app, um agente ou um daemon." : "Rodando num terminal.",
        ].compactMap { $0 }.joined(separator: "\n"))
    }

    private func detail(_ p: CLIProcess) -> String {
        [
            "PID \(p.pid)",
            p.project == nil ? nil : names[p.cli] ?? p.cli,
            p.started.map { Format.relative($0).replacingOccurrences(of: "há ", with: "") },
            "\(Int(p.cpu.rounded()))% CPU",
        ].compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder
    private func stopButton(_ p: CLIProcess) -> some View {
        if monitor.needsForce(p.pid) {
            action("Forçar", color: .red) { monitor.stop(p.pid, force: true) }
        } else if monitor.stopping[p.pid] != nil {
            ProgressView().controlSize(.mini).frame(width: 40)
        } else if armed == p.pid {
            action("Parar", color: .red) {
                armed = nil
                monitor.stop(p.pid)
            }
        } else {
            Button {
                armed = p.pid
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { if armed == p.pid { armed = nil } }
            } label: {
                Image(systemName: "stop.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Parar o processo \(p.pid) (clique de novo para confirmar)")
        }
    }

    private func action(_ title: String, color: Color, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(color))
                .frame(width: 40, alignment: .trailing)
        }
        .buttonStyle(.plain)
    }
}
