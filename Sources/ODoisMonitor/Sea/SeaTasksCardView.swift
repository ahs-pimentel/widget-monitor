import SwiftUI

/// Paleta do card de tarefas.
enum SeaStyle {
    static let teal = Color(red: 0.05, green: 0.62, blue: 0.78)
    static let indigo = Color(red: 0.33, green: 0.30, blue: 0.92)
    static let hero = LinearGradient(colors: [teal, indigo], startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Cor estável por projeto (hash próprio: o `hashValue` do Swift muda a cada execução).
    static func color(for slug: String) -> Color {
        let sum = slug.unicodeScalars.reduce(UInt32(7)) { ($0 &* 31) &+ $1.value }
        return Color(hue: Double(sum % 360) / 360, saturation: 0.65, brightness: 0.72)
    }
}

/// Card das tarefas do Sea Dashboard: cronômetro em destaque, notificações e as tarefas
/// "em andamento" e "não iniciado" agrupadas por projeto.
struct SeaTasksCardView: View {
    @ObservedObject var sea: SeaStore
    var showHeaderIcon = true

    var body: some View {
        VStack(alignment: .leading, spacing: CardMetrics.spacing) {
            header
            if let message = sea.message {
                Label(message, systemImage: "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }
            hero
            pausedTimers
            notificationsBox
            if let error = sea.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            list
        }
        .animation(.easeOut(duration: 0.2), value: sea.timers)
    }

    // MARK: - Cabeçalho

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            if showHeaderIcon {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(SeaStyle.hero)
                    .frame(width: 24, height: 24)
                    .overlay(Image(systemName: "timer").font(.system(size: 12, weight: .bold)).foregroundStyle(.white))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Tarefas").font(.system(size: 13, weight: .semibold))
                if let account = sea.account {
                    // Só o nome; o e-mail fica no tooltip (o card é estreito).
                    Label(account.components(separatedBy: " · ").first ?? account, systemImage: "person.crop.circle")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.tail)
                        .help("Conta logada na CLI sea: \(account)")
                }
                counters
            }
            Spacer(minLength: 4)
            Button { sea.refresh(); sea.fetchNotifications() } label: {
                Group {
                    if sea.loading {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .bold))
                    }
                }
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.primary.opacity(0.07)))
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Atualizar do Dashboard")
        }
    }

    @ViewBuilder
    private var counters: some View {
        if sea.loading && sea.updatedAt == nil {
            Text("Carregando do Dashboard…").font(.system(size: 10)).foregroundStyle(.secondary)
        } else {
            let doing = sea.tasks.filter(\.isInProgress).count
            let todo = sea.tasks.count - doing
            HStack(spacing: 5) {
                chip("\(doing) em andamento", .blue)
                chip("\(todo) a iniciar", .gray)
            }
        }
    }

    private func chip(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.16)))
            .foregroundStyle(color == .gray ? Color.secondary : color)
    }

    // MARK: - Cronômetro em destaque

    @ViewBuilder
    private var hero: some View {
        if let t = sea.running {
            runningHero(t)
        } else if sea.timers.isEmpty, !sea.tasks.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "play.circle")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(SeaStyle.teal)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Escolha uma tarefa para começar").font(.system(size: 11, weight: .semibold))
                    Text("O tempo vira lançamento no Dashboard ao finalizar.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(CardMetrics.boxPadding)
            .background(
                RoundedRectangle(cornerRadius: CardMetrics.boxRadius, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color.primary.opacity(0.18))
            )
        }
    }

    private func runningHero(_ t: TaskTimer) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let elapsed = t.elapsed(now: ctx.date)
            let tick = Int(ctx.date.timeIntervalSince1970) % 2 == 0
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 6, height: 6)
                        .opacity(tick ? 1 : 0.35)
                        .animation(.easeInOut(duration: 0.8), value: tick)
                    Text("GRAVANDO").font(.system(size: 9, weight: .heavy)).tracking(1)
                    Spacer()
                    Text(t.task.projectName)
                        .font(.system(size: 9, weight: .semibold))
                        .lineLimit(1).truncationMode(.tail)
                        .opacity(0.8)
                }
                HStack(alignment: .center, spacing: 12) {
                    ring(elapsed)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(SeaStore.clock(elapsed))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Button { sea.open(t.task) } label: {
                            Text(t.task.title)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1).truncationMode(.tail)
                                .underline(false)
                        }
                        .buttonStyle(.plain)
                        .help("Abrir no Dashboard")
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    if sea.busy.contains(t.task.id) {
                        ProgressView().controlSize(.small).tint(.white)
                        Text("Enviando ao Dashboard…").font(.system(size: 10, weight: .medium))
                    } else {
                        heroButton("pause.fill", "Pausar") { sea.pause(t.task.id) }
                        heroButton("checkmark", "Finalizar", prominent: true) { sea.finish(t.task.id) }
                    }
                    Spacer()
                    Button { sea.discard(t.task.id) } label: {
                        Image(systemName: "trash").font(.system(size: 10, weight: .semibold))
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .help("Descartar sem registrar")
                }
            }
            .foregroundStyle(.white)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(SeaStyle.hero)
                    .shadow(color: SeaStyle.indigo.opacity(0.35), radius: 10, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18))
            )
        }
    }

    /// Anel com o progresso da hora corrente do cronômetro e as horas completas no centro.
    private func ring(_ elapsed: TimeInterval) -> some View {
        let minuteFraction = elapsed.truncatingRemainder(dividingBy: 3600) / 3600
        return ZStack {
            Circle().stroke(Color.white.opacity(0.2), lineWidth: 4)
            Circle()
                .trim(from: 0, to: max(0.01, minuteFraction))
                .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: -2) {
                Text("\(Int(elapsed) / 3600)").font(.system(size: 15, weight: .bold, design: .rounded))
                Text("h").font(.system(size: 8, weight: .semibold)).opacity(0.8)
            }
        }
        .frame(width: 46, height: 46)
    }

    private func heroButton(_ symbol: String, _ title: String, prominent: Bool = false, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .bold))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(prominent ? Color.white : Color.white.opacity(0.18)))
                .foregroundStyle(prominent ? SeaStyle.indigo : Color.white)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pausados

    @ViewBuilder
    private var pausedTimers: some View {
        let paused = sea.timers.values.filter { !$0.isRunning }.sorted { $0.startedAt < $1.startedAt }
        if !paused.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                SectionTitle("Pausados", detail: "\(paused.count)")
                ForEach(paused, id: \.task.id) { t in
                    HStack(spacing: 8) {
                        Image(systemName: "pause.circle.fill").foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 0) {
                            taskLink(t.task, font: .system(size: 11, weight: .semibold))
                            Text(t.task.projectName).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Text(SeaStore.clock(t.elapsed()))
                            .font(.system(size: 11, weight: .bold, design: .rounded)).monospacedDigit()
                        if sea.busy.contains(t.task.id) {
                            ProgressView().controlSize(.mini)
                        } else {
                            circleButton("play.fill", SeaStyle.teal, help: "Retomar") { sea.start(t.task) }
                            circleButton("checkmark", .green, help: "Finalizar e registrar") { sea.finish(t.task.id) }
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.orange.opacity(0.08)))
                }
            }
        }
    }

    private func circleButton(_ symbol: String, _ color: Color, help: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(color.gradient))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Notificações

    @ViewBuilder
    private var notificationsBox: some View {
        if !sea.notifications.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "bell.fill").font(.system(size: 9)).foregroundStyle(SeaStyle.teal)
                    SectionTitle("Notificações")
                    Text("\(sea.notifications.count)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color.red))
                }
                ForEach(sea.notifications.prefix(3)) { n in
                    HStack(alignment: .top, spacing: 8) {
                        Button { sea.open(n) } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 4) {
                                    Text(n.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                                    if let date = n.createdAt {
                                        Text(Format.relative(date)).font(.system(size: 9)).foregroundStyle(.tertiary)
                                    }
                                }
                                Text(n.body).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Abrir no Dashboard e marcar como lida")
                        Button { sea.markRead(n) } label: {
                            Image(systemName: "checkmark").font(.system(size: 8, weight: .bold))
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(Color.primary.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Marcar como lida")
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous).fill(SeaStyle.teal.opacity(0.08))
                    )
                    .overlay(alignment: .leading) {
                        Capsule().fill(SeaStyle.teal).frame(width: 2.5).padding(.vertical, 6)
                    }
                }
            }
        }
    }

    // MARK: - Tarefas

    @ViewBuilder
    private var list: some View {
        let free = sea.tasks.filter { sea.timers[$0.id] == nil }
        if !free.isEmpty {
            let groups = Dictionary(grouping: free, by: \.projectSlug)
                .map { (slug: $0.key, name: $0.value[0].projectName, tasks: $0.value) }
                .sorted { $0.name < $1.name }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(groups, id: \.slug) { group in
                    projectGroup(slug: group.slug, name: group.name, tasks: group.tasks)
                }
            }
        } else if sea.updatedAt != nil, sea.timers.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.green)
                Text("Tudo em dia").font(.system(size: 12, weight: .semibold))
                Text("Nenhuma tarefa em aberto ou em andamento atribuída a você.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }

    private func projectGroup(slug: String, name: String, tasks: [SeaTask]) -> some View {
        let open = !sea.collapsed.contains(slug)
        let color = SeaStyle.color(for: slug)
        return VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { sea.toggleCollapsed(slug) }
            } label: {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 3, height: 12)
                    Text(name)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1).truncationMode(.tail)
                    Text("\(tasks.count)")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(color.opacity(0.2)))
                        .foregroundStyle(color)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                VStack(spacing: 3) {
                    ForEach(tasks) { row($0, color: color) }
                }
                .transition(.opacity)
            }
        }
    }

    private func row(_ task: SeaTask, color: Color) -> some View {
        HStack(spacing: 8) {
            Text("#\(task.number)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(color.opacity(0.16)))
                .foregroundStyle(color)
            Button { sea.open(task) } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(task.subject.trimmingCharacters(in: .whitespaces))
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1).truncationMode(.tail)
                    Text(task.isInProgress ? "Em andamento" : "Não iniciado")
                        .font(.system(size: 9))
                        .foregroundStyle(task.isInProgress ? Color.blue : Color.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Abrir no Dashboard")
            if sea.busy.contains(task.id) {
                ProgressView().controlSize(.mini).frame(width: 24)
            } else {
                Button { sea.start(task) } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(SeaStyle.hero))
                        .shadow(color: SeaStyle.teal.opacity(0.35), radius: 3, y: 1)
                }
                .buttonStyle(.plain)
                .help(task.statusId == SeaTask.notStarted ? "Iniciar (passa a em andamento no Dashboard)" : "Iniciar cronômetro")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.045)))
    }

    /// Título da tarefa que abre a página dela no Dashboard (navegador padrão).
    private func taskLink(_ task: SeaTask, font: Font) -> some View {
        Button { sea.open(task) } label: {
            Text(task.title)
                .font(font)
                .lineLimit(1).truncationMode(.tail)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Abrir no Dashboard")
    }
}
