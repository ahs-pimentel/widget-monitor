import SwiftUI

struct SystemView: View {
    let state: MonitorState
    @ObservedObject var repo: Repository
    @State private var confirm: CliProcess?

    var body: some View {
        let s = state.system
        VStack(spacing: 14) {
            Card {
                SectionTitle(title: state.host ?? "Mac", detail: "atualiza a cada 2 s")
                HStack {
                    big("CPU", s.cpu, .blue, "")
                    big("RAM", s.ramFraction, s.pressureLevel == "normal" ? .purple : Palette.pressure(s.pressureLevel), "de \(Fmt.bytes(s.ramTotal))")
                    big("GPU", s.gpu ?? 0, .orange, "")
                }
            }
            Card {
                HStack {
                    SectionTitle(title: "Pressão de memória")
                    Circle().fill(Palette.pressure(s.pressureLevel)).frame(width: 7, height: 7)
                    Text("\(pressureLabel(s.pressureLevel)) · \(Int(s.pressure * 100))%").font(.caption.weight(.semibold)).foregroundStyle(Palette.pressure(s.pressureLevel)).fixedSize()
                }
                Bars(values: s.pressureHistory ?? [], color: Palette.pressure(s.pressureLevel)).frame(height: 40)
                Text("Swap \(Fmt.bytes(s.swapUsed)) de \(Fmt.bytes(s.swapTotal))").font(.caption).foregroundStyle(Palette.secondary)
                SectionTitle(title: "CPU · últimos 2 min")
                Bars(values: s.cpuHistory ?? [], color: .blue).frame(height: 32)
            }
            Card {
                let bg = state.processes.filter(\.background).count
                SectionTitle(title: "Processos das CLIs", detail: state.processes.isEmpty ? nil : "\(state.processes.count) · \(bg) em 2º plano")
                if state.processes.isEmpty { Text("Nenhuma CLI de LLM rodando agora.").font(.subheadline).foregroundStyle(Palette.secondary) }
                ForEach(Array(state.processes.enumerated()), id: \.element.id) { i, p in
                    if i > 0 { Divider().overlay(.white.opacity(0.08)) }
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(p.project ?? p.cliName).font(.subheadline.weight(.semibold)).lineLimit(1)
                                if p.background { Chip(text: "2º plano", color: .orange) }
                            }
                            Text(["PID \(p.pid)", p.cliName, Fmt.relative(p.startedAt).replacingOccurrences(of: "há ", with: ""), "\(Int(p.cpu))% CPU", Fmt.bytes(p.memory)].joined(separator: " · "))
                                .font(.caption).foregroundStyle(Palette.secondary).lineLimit(1)
                        }
                        Spacer()
                        if p.stopping == true {
                            Button("Forçar") { stop(p, force: true) }.tint(.red).buttonStyle(.bordered)
                        } else {
                            Button { confirm = p } label: { Image(systemName: "stop.circle").font(.title2) }.tint(Palette.secondary)
                        }
                    }
                }
            }
        }
        .confirmationDialog(confirm.map { "Parar o processo \($0.pid)?" } ?? "", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), titleVisibility: .visible) {
            if let p = confirm {
                Button("Parar (SIGTERM)", role: .destructive) { stop(p, force: false) }
                Button("Forçar (SIGKILL)", role: .destructive) { stop(p, force: true) }
                Button("Cancelar", role: .cancel) {}
            }
        } message: {
            if let p = confirm { Text("\(p.cliName)\(p.project.map { " · \($0)" } ?? ""). O trabalho em andamento nessa sessão pode ser perdido.") }
        }
    }

    private func stop(_ p: CliProcess, force: Bool) {
        confirm = nil
        repo.act(force ? "Processo \(p.pid) encerrado" : "Pedido de parada enviado a \(p.pid)") { try await $0.stopProcess(p.pid, force: force) }
    }

    private func big(_ label: String, _ value: Double, _ color: Color, _ detail: String) -> some View {
        VStack(spacing: 6) {
            Ring(value: value, color: color, lineWidth: 7) {
                VStack(spacing: 0) {
                    Text(Fmt.percent(value)).font(.headline.bold())
                    Text(label).font(.caption2.weight(.semibold)).foregroundStyle(Palette.secondary)
                }
            }
            .frame(width: 76, height: 76)
            if !detail.isEmpty { Text(detail).font(.caption2).foregroundStyle(Palette.secondary) }
        }
        .frame(maxWidth: .infinity)
    }
}
