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

    /// Preenche o submenu de processos na hora em que abre (a lista muda a cada 2 s).
    func menuNeedsUpdate(_ sub: NSMenu) {
        sub.removeAllItems()
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
