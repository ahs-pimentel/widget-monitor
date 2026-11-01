import AppIntents

/// Atalhos da Siri e do app Atalhos: pausar o cronômetro e retomar/iniciar a tarefa em andamento.
struct PauseTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Pausar cronômetro"
    static var description = IntentDescription("Pausa o cronômetro da tarefa em andamento no Mac.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let client = Repository.shared.client else { return .result(dialog: "Pareie o iPhone com o Mac primeiro.") }
        let state = try await client.state()
        guard let running = state.sea?.running else { return .result(dialog: "Nenhum cronômetro rodando.") }
        _ = try await client.pauseTimer(running.task.id)
        return .result(dialog: "Cronômetro de \(running.task.title) pausado.")
    }
}

struct ResumeTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Retomar tarefa"
    static var description = IntentDescription("Retoma o cronômetro pausado mais recente ou inicia a primeira tarefa em andamento.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let client = Repository.shared.client else { return .result(dialog: "Pareie o iPhone com o Mac primeiro.") }
        let state = try await client.state()
        guard let sea = state.sea else { return .result(dialog: "A CLI sea não está configurada no Mac.") }
        if let running = sea.running { return .result(dialog: "\(running.task.title) já está rodando.") }
        guard let task = sea.timers.last?.task ?? sea.tasks.first(where: \.inProgress) else {
            return .result(dialog: "Nenhuma tarefa em andamento.")
        }
        _ = try await client.startTask(task.id)
        return .result(dialog: "Cronômetro de \(task.title) iniciado.")
    }
}

struct MonitorShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PauseTimerIntent(), phrases: ["Pausar cronômetro no \(.applicationName)"], shortTitle: "Pausar cronômetro", systemImageName: "pause.circle")
        AppShortcut(intent: ResumeTaskIntent(), phrases: ["Retomar tarefa no \(.applicationName)"], shortTitle: "Retomar tarefa", systemImageName: "play.circle")
    }
}
