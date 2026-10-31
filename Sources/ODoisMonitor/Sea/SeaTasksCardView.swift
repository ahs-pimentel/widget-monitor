import SwiftUI

/// Card das tarefas do Sea Dashboard: cronômetro em andamento no topo e, abaixo,
/// as tarefas "em andamento" e "não iniciado" por projeto, cada uma com play/pausa.
struct SeaTasksCardView: View {
    @ObservedObject var sea: SeaStore
    var showHeaderIcon = true

    var body: some View {
        VStack(alignment: .leading, spacing: CardMetrics.spacing) {
            header
            if let message = sea.message {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green)
            }
            timersBox
            if let error = sea.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 10)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            list
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if showHeaderIcon {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(nsColor: SeaProvider().tint).gradient)
                    .frame(width: 24, height: 24)
                    .overlay(Image(systemName: "timer").font(.system(size: 12, weight: .bold)).foregroundStyle(.white))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Tarefas").font(.system(size: 13, weight: .semibold))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { sea.refresh() } label: {
                Group {
                    if sea.loading {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold))
                    }
                }
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Atualizar do Dashboard")
        }
    }

    private var subtitle: String {
        if sea.loading && sea.updatedAt == nil { return "Carregando do Dashboard…" }
        let open = sea.tasks.count
        return open == 0 ? "Nenhuma tarefa aberta" : "\(open) \(open == 1 ? "aberta" : "abertas") · Sea Dashboard"
    }

    // MARK: - Cronômetros

    @ViewBuilder
    private var timersBox: some View {
        let timers = sea.timers.values.sorted { ($0.isRunning ? 0 : 1, $0.startedAt) < ($1.isRunning ? 0 : 1, $1.startedAt) }
        if !timers.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(timers, id: \.task.id) { timer($0) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(InsetBox())
        }
    }

    private func timer(_ t: TaskTimer) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.task.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text(t.task.projectName).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 6)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(SeaStore.clock(t.elapsed(now: ctx.date)))
                        .font(.system(size: t.isRunning ? 18 : 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(t.isRunning ? Color.primary : Color.secondary)
                }
            }
            HStack(spacing: 6) {
                if sea.busy.contains(t.task.id) {
                    ProgressView().controlSize(.small)
                    Text("Enviando…").font(.system(size: 10)).foregroundStyle(.secondary)
                } else {
                    pill(t.isRunning ? "Pausar" : "Retomar", t.isRunning ? "pause.fill" : "play.fill", .accentColor) {
                        sea.toggle(t.task)
                    }
                    pill("Finalizar", "checkmark", .green) { sea.finish(t.task.id) }
                }
                Spacer()
                Button { sea.discard(t.task.id) } label: {
                    Image(systemName: "trash").font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Descartar o cronômetro sem registrar")
            }
        }
    }

    private func pill(_ title: String, _ symbol: String, _ color: Color, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Label(title, systemImage: symbol)
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(color.opacity(0.18)))
                .foregroundStyle(color)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tarefas

    @ViewBuilder
    private var list: some View {
        let free = sea.tasks.filter { sea.timers[$0.id] == nil }
        if !free.isEmpty {
            let groups = Dictionary(grouping: free, by: \.projectName).sorted { $0.key < $1.key }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(groups, id: \.key) { project, tasks in
                    VStack(alignment: .leading, spacing: 4) {
                        SectionTitle(project, detail: "\(tasks.count)")
                        ForEach(tasks) { row($0) }
                    }
                }
            }
        } else if sea.updatedAt != nil, sea.timers.isEmpty {
            Text("Nenhuma tarefa em aberto ou em andamento atribuída a você.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ task: SeaTask) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(task.isInProgress ? Color.blue : Color.gray.opacity(0.6))
                .frame(width: 6, height: 6)
                .help(task.isInProgress ? "Em andamento" : "Não iniciado")
            Text(task.title)
                .font(.system(size: 11))
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            if sea.busy.contains(task.id) {
                ProgressView().controlSize(.mini)
            } else {
                Button { sea.start(task) } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.accentColor)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(task.statusId == SeaTask.notStarted ? "Iniciar (passa a em andamento no Dashboard)" : "Iniciar cronômetro")
            }
        }
        .padding(.vertical, 2)
    }
}
