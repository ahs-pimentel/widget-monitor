import AppKit
import ServiceManagement

/// Menu do clique direito (barra e notch) e suas ações.
extension AppDelegate: NSMenuDelegate {
    // MARK: - Menu

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(item("Atualizar agora", #selector(refreshNow), "r"))
        menu.addItem(item("Procurar CLIs de novo", #selector(redetect), ""))
        menu.addItem(.separator())
        let notchItem = item("Acoplar ao notch da câmera", #selector(toggleNotch), "")
        notchItem.state = notchMode ? .on : .off
        menu.addItem(notchItem)
        menu.addItem(.separator())
        let vertical = barState.orientation == .vertical
        let orient = item(vertical ? "Deixar na horizontal" : "Deixar na vertical", #selector(toggleOrientation), "")
        // Colada, a orientação acompanha a borda.
        orient.isEnabled = !isDocked && !notchMode
        menu.addItem(orient)
        let snap = item("Colar na borda da tela", #selector(toggleSnap), "")
        snap.state = snapToEdge ? .on : .off
        snap.isEnabled = !notchMode
        menu.addItem(snap)
        let center = item("Voltar para o centro", #selector(recenter), "")
        center.isEnabled = !notchMode
        menu.addItem(center)
        let hide = item("Ocultar automaticamente", #selector(toggleAutoHide), "")
        hide.state = autoHide ? .on : .off
        hide.isEnabled = !notchMode
        menu.addItem(hide)
        menu.addItem(.separator())
        let alertsItem = item("Alertas", #selector(toggleAlerts), "")
        alertsItem.state = alerts.enabled ? .on : .off
        menu.addItem(alertsItem)
        menu.addItem(item("Enviar alerta de teste", #selector(testAlert), ""))
        let sessions = item("Mostrar sessões recentes", #selector(toggleSessions), "")
        sessions.state = UserDefaults.standard.bool(forKey: ProviderCardView.sessionsKey) ? .on : .off
        menu.addItem(sessions)
        let login = item("Abrir ao iniciar sessão", #selector(toggleLogin), "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        if SeaStore.shared.isAvailable { menu.addItem(tasksMenuItem()) }
        menu.addItem(remoteMenuItem())
        menu.addItem(processesMenuItem())
        menu.addItem(.separator())
        let about = NSMenuItem(title: "oDois Monitor \(AppInfo.versionLabel)", action: nil, keyEquivalent: "")
        about.isEnabled = false
        menu.addItem(about)
        menu.addItem(item("Sair", #selector(quit), "q"))
        return menu
    }

    func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
        it.target = self
        return it
    }

    func rebuildMenu() { bar?.contentView?.menu = makeMenu() }

    @objc private func refreshNow() { store.refreshAll() }

    @objc private func redetect() {
        store.detect()
        store.refreshAll()
    }

    @objc private func toggleOrientation() {
        setOrientation(barState.orientation == .horizontal ? .vertical : .horizontal)
        resizeBar()
    }

    @objc private func recenter() {
        UserDefaults.standard.removeObject(forKey: Keys.origin)
        lastNear = Date()
        setBarShown(true)
        if snapToEdge {
            // Centro da borda de baixo da tela principal.
            let screen = NSScreen.main ?? bar.screen
            guard let area = screen?.visibleFrame else { return }
            dockedScreen = screen
            dockedEdge = .bottom
            UserDefaults.standard.set(ScreenEdge.bottom.rawValue, forKey: Keys.edge)
            dockCenter = CGPoint(x: area.midX, y: area.minY)
            setOrientation(.horizontal)
            placeDocked(animate: true)
        } else {
            bar.setFrameOrigin(initialOrigin(for: bar.frame.size))
            saveOrigin()
        }
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Não foi possível alterar a abertura automática"
            alert.informativeText = "\(error.localizedDescription)\nRode o app a partir do oDois Monitor.app (scripts/build-app.sh)."
            alert.runModal()
        }
        rebuildMenu()
    }

    @objc private func toggleAlerts() {
        alerts.enabled.toggle()
        rebuildMenu()
    }

    @objc private func testAlert() { alerts.sendTest() }

    // MARK: - Processos

    /// Submenu com os processos das CLIs; escolher um pede confirmação para parar.
    private func processesMenuItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "Processos das CLIs", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.delegate = self
        parent.submenu = sub
        return parent
    }

    /// Preenche os submenus na hora em que abrem (processos mudam a cada 2 s; tarefas, ao usar).
    func menuNeedsUpdate(_ sub: NSMenu) {
        sub.removeAllItems()
        if sub.identifier == Self.tasksMenuID {
            fillTasksMenu(sub)
            return
        }
        let list = SystemMonitor.shared.cliProcesses
        if list.isEmpty {
            let empty = NSMenuItem(title: "Nenhuma CLI rodando", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            sub.addItem(empty)
        }
        let names = Dictionary(uniqueKeysWithValues: store.items.map { ($0.id, $0.provider.name) })
        for p in list {
            let title = [names[p.cli] ?? p.cli, "PID \(p.pid)", p.project, p.background ? "2º plano" : nil, Bytes.format(p.memory)]
                .compactMap { $0 }.joined(separator: " · ")
            let entry = NSMenuItem(title: title, action: #selector(confirmStop(_:)), keyEquivalent: "")
            entry.target = self
            entry.tag = Int(p.pid)
            sub.addItem(entry)
        }
    }

    // MARK: - Acesso remoto

    private func remoteMenuItem() -> NSMenuItem {
        let access = RemoteAccess.shared
        let parent = NSMenuItem(title: "Acesso remoto (celular)", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let status = NSMenuItem(title: "Status: \(access.status.label)", action: nil, keyEquivalent: "")
        status.isEnabled = false
        sub.addItem(status)
        if let url = access.publicURL {
            let address = NSMenuItem(title: url.absoluteString, action: nil, keyEquivalent: "")
            address.isEnabled = false
            sub.addItem(address)
        }
        sub.addItem(.separator())
        let toggle = item("Ativar acesso remoto", #selector(toggleRemote), "")
        toggle.state = access.enabled ? .on : .off
        sub.addItem(toggle)
        sub.addItem(item("Parear celular…", #selector(pairPhone), ""))
        let devices = access.devices.filter { $0.lastSeenAt != nil }
        if !devices.isEmpty {
            sub.addItem(.separator())
            for d in devices {
                let entry = NSMenuItem(title: "Revogar \(d.name)", action: #selector(revokeDevice(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = d.id
                entry.toolTip = d.lastSeenAt.map { "Último acesso \(Format.relative($0))" }
                sub.addItem(entry)
            }
        }
        parent.submenu = sub
        return parent
    }

    @objc private func toggleRemote() {
        RemoteAccess.shared.toggle()
        rebuildMenu()
    }

    @objc private func pairPhone() { PairingWindow.shared.show() }

    @objc private func revokeDevice(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        RemoteAccess.shared.revoke(id)
        rebuildMenu()
    }

    // MARK: - Tarefas Sea

    static let tasksMenuID = NSUserInterfaceItemIdentifier("seaTasks")

    private func tasksMenuItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "Tarefas Sea", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.identifier = Self.tasksMenuID
        sub.delegate = self
        parent.submenu = sub
        return parent
    }

    /// No modo barra o card não recebe clique: o cronômetro é controlado por aqui.
    private func fillTasksMenu(_ sub: NSMenu) {
        let sea = SeaStore.shared
        for t in sea.timers.values.sorted(by: { $0.startedAt < $1.startedAt }) {
            let header = NSMenuItem(title: "\(t.isRunning ? "⏱" : "⏸") \(SeaStore.clock(t.elapsed())) · \(t.task.title)", action: nil, keyEquivalent: "")
            header.isEnabled = false
            sub.addItem(header)
            sub.addItem(taskAction(t.isRunning ? "Pausar" : "Retomar", #selector(seaToggle(_:)), t.task.id))
            sub.addItem(taskAction("Finalizar e registrar…", #selector(seaFinish(_:)), t.task.id))
            sub.addItem(taskAction("Abrir no navegador", #selector(seaOpen(_:)), t.task.id))
            sub.addItem(taskAction("Descartar…", #selector(seaDiscard(_:)), t.task.id))
            sub.addItem(.separator())
        }
        let free = sea.tasks.filter { sea.timers[$0.id] == nil }
        if free.isEmpty {
            let empty = NSMenuItem(title: sea.loading ? "Carregando…" : "Nenhuma tarefa aberta", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            sub.addItem(empty)
        }
        for task in free {
            let entry = NSMenuItem(title: task.title, action: nil, keyEquivalent: "")
            entry.toolTip = task.projectName + (task.isInProgress ? " · em andamento" : " · não iniciado")
            let actions = NSMenu()
            actions.addItem(taskAction("▶ Iniciar cronômetro", #selector(seaToggle(_:)), task.id))
            actions.addItem(taskAction("Abrir no navegador", #selector(seaOpen(_:)), task.id))
            entry.submenu = actions
            sub.addItem(entry)
        }
        sub.addItem(.separator())
        sub.addItem(item("Atualizar tarefas", #selector(seaRefresh), ""))
    }

    private func taskAction(_ title: String, _ action: Selector, _ id: Int) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        entry.tag = id
        return entry
    }

    private func seaTask(_ id: Int) -> SeaTask? {
        SeaStore.shared.timers[id]?.task ?? SeaStore.shared.tasks.first { $0.id == id }
    }

    @objc private func seaToggle(_ sender: NSMenuItem) {
        if let task = seaTask(sender.tag) { SeaStore.shared.toggle(task) }
    }

    @objc private func seaFinish(_ sender: NSMenuItem) { SeaStore.shared.finish(sender.tag) }
    @objc private func seaDiscard(_ sender: NSMenuItem) { SeaStore.shared.discard(sender.tag) }
    @objc private func seaRefresh() { SeaStore.shared.refresh() }
    @objc private func seaOpen(_ sender: NSMenuItem) {
        if let task = seaTask(sender.tag) { SeaStore.shared.open(task) }
    }

    @objc private func confirmStop(_ sender: NSMenuItem) {
        let pid = pid_t(sender.tag)
        let alert = NSAlert()
        alert.messageText = "Parar o processo \(pid)?"
        alert.informativeText = sender.title + "\n\n\"Parar\" pede para encerrar (SIGTERM); \"Forçar\" encerra na hora (SIGKILL)."
        alert.addButton(withTitle: "Parar")
        alert.addButton(withTitle: "Forçar")
        alert.addButton(withTitle: "Cancelar")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn: SystemMonitor.shared.stop(pid)
        case .alertSecondButtonReturn: SystemMonitor.shared.stop(pid, force: true)
        default: break
        }
    }

    /// No modo barra o card não recebe clique; o menu abre e fecha as sessões.
    @objc private func toggleSessions() {
        let key = ProviderCardView.sessionsKey
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: key), forKey: key)
        rebuildMenu()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

/// Versão do app lida do Info.plist (gerado pelo build-app.sh a partir de VERSION).
enum AppInfo {
    static var versionLabel: String {
        let info = Bundle.main.infoDictionary
        guard let version = info?["CFBundleShortVersionString"] as? String else { return "(dev)" }
        let build = info?["CFBundleVersion"] as? String
        return "v\(version)" + (build.map { " (\($0))" } ?? "")
    }
}
