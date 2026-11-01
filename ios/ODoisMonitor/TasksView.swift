import SwiftUI

struct TasksView: View {
    let sea: Sea
    let now: Date
    let receivedAt: Date
    @ObservedObject var repo: Repository
    @Environment(\.openURL) private var openURL
    @State private var finishing: TaskTimer?
    @State private var discarding: TaskTimer?
    @AppStorage("collapsedProjects") private var collapsedRaw = ""

    private var collapsed: Set<String> { Set(collapsedRaw.split(separator: ",").map(String.init)) }
    private func toggle(_ slug: String) {
        var set = collapsed
        if set.contains(slug) { set.remove(slug) } else { set.insert(slug) }
        collapsedRaw = set.sorted().joined(separator: ",")
    }
    private func open(_ url: String?) { if let url, let u = URL(string: url) { openURL(u) } }

    var body: some View {
        VStack(spacing: 14) {
            header
            if let message = sea.message { Label(message, systemImage: "checkmark.seal.fill").font(.subheadline.weight(.semibold)).foregroundStyle(.green).frame(maxWidth: .infinity, alignment: .leading) }
            if let r = sea.ranking { ranking(r) }
            if let t = sea.running { hero(t) }
            paused
            notifications
            projects
            if let error = sea.error { Label(error, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange) }
        }
        .sheet(item: Binding(get: { finishing.map(TimerBox.init) }, set: { finishing = $0?.timer })) { box in
            FinishSheet(timer: box.timer, now: now, receivedAt: receivedAt, repo: repo)
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog("Descartar o cronômetro?", isPresented: Binding(get: { discarding != nil }, set: { if !$0 { discarding = nil } }), titleVisibility: .visible) {
            if let t = discarding {
                Button("Descartar", role: .destructive) { repo.act("Cronômetro descartado") { try await $0.discardTimer(t.task.id) } }
                Button("Cancelar", role: .cancel) {}
            }
        } message: {
            if let t = discarding { Text("\(Fmt.clock(t.elapsed(at: now, receivedAt: receivedAt))) de \(t.task.title) não serão registrados no Dashboard.") }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            RemoteImage(path: "/v1/avatar.png") {
                ZStack { Palette.hero; Text(initials(sea.accountName)).font(.headline).foregroundStyle(.white) }
            }
            .frame(width: 48, height: 48).clipShape(Circle())
            .padding(2).background(Circle().fill(Palette.hero))
            VStack(alignment: .leading, spacing: 4) {
                Text(sea.accountName ?? "Tarefas").font(.title3.bold())
                let doing = sea.tasks.filter(\.inProgress).count
                HStack(spacing: 6) {
                    Chip(text: "\(doing) em andamento", color: .blue)
                    Chip(text: "\(sea.tasks.count - doing) a iniciar", color: Palette.secondary)
                }
            }
            Spacer()
            if sea.loading == true { ProgressView() }
        }
    }

    private func ranking(_ r: Ranking) -> some View {
        Card(gradient: LinearGradient(colors: [.orange.opacity(0.22), .orange.opacity(0.05)], startPoint: .leading, endPoint: .trailing)) {
            HStack {
                Image(systemName: "trophy.fill").foregroundStyle(.white).frame(width: 36, height: 36)
                    .background(Circle().fill(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)))
                Text(r.position.map { "\($0)º" + (r.total.map { " de \($0)" } ?? "") } ?? "Ranking \(String(r.year))").font(.title3.bold())
                Spacer()
                Text("\(Fmt.number(r.score)) pts").font(.title3.weight(.black)).monospacedDigit()
            }
        }
    }

    private func hero(_ t: TaskTimer) -> some View {
        let elapsed = t.elapsed(at: now, receivedAt: receivedAt)
        return Card(gradient: Palette.hero) {
            HStack(spacing: 6) {
                Circle().fill(.white).frame(width: 7, height: 7).opacity(Int(now.timeIntervalSince1970) % 2 == 0 ? 1 : 0.35)
                Text("GRAVANDO").font(.caption2.weight(.heavy)).tracking(1)
                Spacer()
                Text(t.task.projectName).font(.caption2.weight(.semibold)).opacity(0.85).lineLimit(1)
            }
            HStack(spacing: 16) {
                Ring(value: max(0.01, elapsed.truncatingRemainder(dividingBy: 3600) / 3600), color: .white, lineWidth: 5) {
                    VStack(spacing: -2) {
                        Text("\(Int(elapsed) / 3600)").font(.title2.bold())
                        Text("h").font(.caption2).opacity(0.8)
                    }
                }
                .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Fmt.clock(elapsed)).font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit().contentTransition(.numericText())
                    Button { open(t.task.url) } label: { Text(t.task.title).font(.subheadline.weight(.semibold)).lineLimit(1) }.buttonStyle(.plain)
                }
            }
            HStack(spacing: 10) {
                if t.task.busy == true {
                    ProgressView().tint(.white)
                    Text("Enviando ao Dashboard…")
                } else {
                    Button { repo.act { try await $0.pauseTimer(t.task.id) } } label: { Label("Pausar", systemImage: "pause.fill") }
                        .buttonStyle(.bordered).tint(.white)
                    Button { finishing = t } label: { Label("Finalizar", systemImage: "checkmark").fontWeight(.bold) }
                        .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(Palette.indigo)
                }
                Spacer()
                Button { discarding = t } label: { Image(systemName: "trash") }.tint(.white)
            }
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder private var paused: some View {
        let list = sea.timers.filter { !$0.running }
        if !list.isEmpty {
            Card {
                SectionTitle(title: "Pausados", detail: "\(list.count)")
                ForEach(list, id: \.task.id) { t in
                    HStack {
                        Button { open(t.task.url) } label: {
                            VStack(alignment: .leading) {
                                Text(t.task.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text(t.task.projectName).font(.caption2).foregroundStyle(Palette.secondary).lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Text(Fmt.clock(t.elapsed)).font(.subheadline.bold()).monospacedDigit()
                        Button { repo.act { try await $0.startTask(t.task.id) } } label: { Image(systemName: "play.circle.fill").font(.title2) }.tint(Palette.teal)
                        Button { finishing = t } label: { Image(systemName: "checkmark.circle.fill").font(.title2) }.tint(.green)
                    }
                }
            }
        }
    }

    @ViewBuilder private var notifications: some View {
        if !sea.notifications.isEmpty {
            Card {
                HStack {
                    Image(systemName: "bell.fill").foregroundStyle(Palette.teal)
                    SectionTitle(title: "Notificações")
                    Text("\(sea.notifications.count)").font(.caption2.bold()).foregroundStyle(.white).padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(.red))
                }
                ForEach(sea.notifications) { n in
                    HStack(alignment: .top) {
                        Button { open(n.url); repo.act { try await $0.markRead(n.id) } } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(n.title).font(.subheadline.weight(.semibold))
                                if let body = n.body { Text(body).font(.caption).foregroundStyle(Palette.secondary).lineLimit(3) }
                                Text(Fmt.relative(n.createdAt, now: now)).font(.caption2).foregroundStyle(Palette.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        Button { repo.act { try await $0.markRead(n.id) } } label: { Image(systemName: "checkmark") }.tint(Palette.secondary)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Palette.teal.opacity(0.1)))
                }
            }
        }
    }

    @ViewBuilder private var projects: some View {
        let running = Set(sea.timers.map(\.task.id))
        let groups = Dictionary(grouping: sea.tasks.filter { !running.contains($0.id) }, by: \.projectSlug)
            .sorted { ($0.value.first?.projectName ?? "") < ($1.value.first?.projectName ?? "") }
        if groups.isEmpty && sea.timers.isEmpty && sea.loading != true {
            Card {
                Text("Tudo em dia ✓").font(.headline)
                Text("Nenhuma tarefa em aberto ou em andamento.").foregroundStyle(Palette.secondary)
            }
        }
        ForEach(groups, id: \.key) { slug, tasks in
            let color = Palette.project(slug)
            let isOpen = !collapsed.contains(slug)
            Card {
                Button { withAnimation(.easeOut(duration: 0.2)) { toggle(slug) } } label: {
                    HStack(spacing: 8) {
                        Capsule().fill(color).frame(width: 4, height: 16)
                        Text(tasks.first?.projectName ?? slug).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Spacer()
                        Chip(text: "\(tasks.count)", color: color)
                        Image(systemName: "chevron.down").font(.caption.bold()).foregroundStyle(Palette.secondary).rotationEffect(.degrees(isOpen ? 0 : -90))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if isOpen {
                    ForEach(tasks) { task in row(task, color: color) }
                }
            }
        }
    }

    private func row(_ task: SeaTask, color: Color) -> some View {
        HStack(spacing: 10) {
            Text("#\(task.number)").font(.caption.monospaced().bold()).foregroundStyle(color)
                .padding(.horizontal, 6).padding(.vertical, 3).background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.16)))
            Button { open(task.url) } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(task.subject).font(.subheadline.weight(.medium)).lineLimit(1)
                    Text(task.inProgress ? "Em andamento" : "Não iniciado").font(.caption2).foregroundStyle(task.inProgress ? .blue : Palette.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            if task.busy == true {
                ProgressView()
            } else {
                Button { repo.act { try await $0.startTask(task.id) } } label: {
                    Image(systemName: "play.fill").font(.caption.bold()).foregroundStyle(.white).frame(width: 36, height: 36).background(Circle().fill(Palette.hero))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.04)))
    }

    private func initials(_ name: String?) -> String {
        let parts = (name ?? "").split(separator: " ")
        return [parts.first?.first, parts.count > 1 ? parts.last?.first : nil].compactMap { $0 }.map(String.init).joined().uppercased()
    }
}

private struct TimerBox: Identifiable {
    let timer: TaskTimer
    var id: Int { timer.task.id }
}

/// Finalizar: horas (editáveis), dia, tipo de atividade e comentário; o Mac grava no Dashboard.
struct FinishSheet: View {
    let timer: TaskTimer
    let now: Date
    let receivedAt: Date
    @ObservedObject var repo: Repository
    @Environment(\.dismiss) private var dismiss
    @State private var hours = ""
    @State private var dayOffset = 0
    @State private var comment = ""
    @State private var types: [ActivityType] = []
    @State private var selected: ActivityType?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section { Text("\(timer.task.title) · \(timer.task.projectName)").foregroundStyle(Palette.secondary) }
                Section("Horas") { TextField("1,5", text: $hours).keyboardType(.decimalPad) }
                Section("Dia") {
                    Picker("Dia", selection: $dayOffset) { Text("Hoje").tag(0); Text("Ontem").tag(1); Text("Anteontem").tag(2) }.pickerStyle(.segmented)
                }
                Section("Atividade") {
                    if types.isEmpty { ProgressView() } else {
                        Picker("Tipo", selection: $selected) { ForEach(types) { Text($0.label).tag(Optional($0)) } }
                    }
                }
                Section("Comentário") { TextField("O que foi feito (opcional)", text: $comment, axis: .vertical).lineLimit(2...5) }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Registrar horas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Registrar") { submit() }.bold() }
            }
        }
        .task {
            let suggested = (timer.elapsed(at: now, receivedAt: receivedAt) / 36).rounded() / 100
            hours = Fmt.number(max(suggested, 0.01))
            guard let result = try? await repo.client?.activityTypes(timer.task.projectSlug) else { error = "Não consegui ler os tipos de atividade."; return }
            types = result.data
            let preferred = result.preferred ?? timer.preferredActivityType
            selected = types.first { $0.id == preferred } ?? types.first { $0.label == "Desenvolvimento" } ?? types.first
        }
    }

    private func submit() {
        guard let h = Double(hours.replacingOccurrences(of: ",", with: ".")), h > 0, h <= 24 else { error = "Informe as horas entre 0 e 24 (ex.: 1,5)."; return }
        guard let type = selected else { error = "Escolha o tipo de atividade."; return }
        let date = Calendar.current.date(byAdding: .day, value: -dayOffset, to: Date()) ?? Date()
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        let id = timer.task.id, title = timer.task.title, text = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        repo.act("\(Fmt.number(h)) h registradas em \(title)") { try await $0.finishTimer(id, hours: h, date: f.string(from: date), activityType: type.id, comment: text) }
        dismiss()
    }
}
