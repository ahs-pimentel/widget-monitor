import AppKit
import ServiceManagement

/// Menu do clique direito (barra e notch) e suas ações.
extension AppDelegate {
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
        let login = item("Abrir ao iniciar sessão", #selector(toggleLogin), "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
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

    @objc private func quit() { NSApp.terminate(nil) }
}
