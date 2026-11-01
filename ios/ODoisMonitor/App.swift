import Combine
import SwiftUI

enum AppTab: Hashable { case overview, clis, mac, tasks }

@main
struct ODoisMonitorApp: App {
    @Environment(\.scenePhase) private var phase

    init() {
        BackgroundRefresh.register()
        // Notificações só são pedidas depois do pareamento (aí o pedido faz sentido).
        #if DEBUG
        let skip = ProcessInfo.processInfo.environment["ODOIS_SKIP_NOTIFICATIONS"] != nil
        #else
        let skip = false
        #endif
        if Keychain.load() != nil, !skip { Alerts.requestPermission() }
    }

    var body: some Scene {
        WindowGroup {
            RootView(repo: .shared)
                .preferredColorScheme(.dark)
                .tint(Palette.teal)
        }
        .onChange(of: phase) { _, newPhase in
            switch newPhase {
            case .active: Repository.shared.startLive()
            case .background:
                Repository.shared.stopLive()
                BackgroundRefresh.schedule()
            default: break
            }
        }
    }
}

struct RootView: View {
    @ObservedObject var repo: Repository
    @State private var tab: AppTab = .overview
    @State private var cli: String?
    @State private var now = Date()
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .bottom) {
            Palette.background.ignoresSafeArea()
            if let pairing = repo.pairing {
                TabView(selection: $tab) {
                    screen(.overview).tabItem { Label("Geral", systemImage: "square.grid.2x2.fill") }.tag(AppTab.overview)
                    screen(.clis).tabItem { Label("CLIs", systemImage: "terminal.fill") }.tag(AppTab.clis)
                    screen(.mac).tabItem { Label("Mac", systemImage: "cpu") }.tag(AppTab.mac)
                    screen(.tasks).tabItem { Label("Tarefas", systemImage: "timer") }.tag(AppTab.tasks)
                }
                .onChange(of: tab) { _, _ in cli = nil }
            } else {
                PairView(repo: repo)
            }
            if let toast = repo.toast {
                Text(toast).font(.subheadline.weight(.semibold)).padding(.horizontal, 16).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Palette.surfaceHigh)).padding(.bottom, 90)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: repo.toast)
        .onReceive(clock) { now = $0 }
        #if DEBUG
        // Só em debug (simulador): pareamento e aba inicial por variáveis de ambiente.
        .task {
            let env = ProcessInfo.processInfo.environment
            if let raw = env["ODOIS_PAIR"], repo.pairing == nil, let message = await repo.pair(raw) { repo.show(message) }
            switch env["ODOIS_TAB"] {
            case "clis": tab = .clis
            case "mac": tab = .mac
            case "tarefas": tab = .tasks
            default: break
            }
            if let id = env["ODOIS_CLI"] { cli = id }
        }
        #endif
        .onOpenURL { url in
            switch url.host {
            case "pair":
                Task { if let message = await repo.pair(url.absoluteString) { repo.show(message) } }
            case "tab":
                // odoismonitor://tab/<geral|clis|mac|tarefas> (widget e atalhos).
                cli = nil
                switch url.lastPathComponent {
                case "clis": tab = .clis
                case "mac": tab = .mac
                case "tarefas": tab = .tasks
                default: tab = .overview
                }
            default: break
            }
        }
    }

    private func header(_ pairing: PairingInfo) -> some View {
        HStack {
            if cli != nil {
                Button { cli = nil } label: { Image(systemName: "chevron.left").font(.headline) }
            }
            Spacer()
            VStack(spacing: 2) {
                Text("oDois Monitor").font(.headline)
                HStack(spacing: 5) {
                    Circle().fill(repo.connection == .live ? .green : repo.connection == .connecting ? .orange : .red).frame(width: 6, height: 6)
                    Text(repo.connection == .live ? (pairing.host ?? "Mac") : repo.connection == .connecting ? "Conectando a \(pairing.host ?? "Mac")…" : "Sem conexão com \(pairing.host ?? "Mac")")
                        .font(.caption2).foregroundStyle(Palette.secondary)
                }
            }
            Spacer()
            Menu {
                Button { repo.act { try await $0.refresh(); return nil } } label: { Label("Atualizar", systemImage: "arrow.clockwise") }
                Button(role: .destructive) { repo.unpair() } label: { Label("Desparear este iPhone", systemImage: "iphone.slash") }
            } label: { Image(systemName: "ellipsis.circle").font(.title3) }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Palette.background)
    }

    @ViewBuilder
    private func screen(_ which: AppTab) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                if let error = repo.error, repo.connection != .live {
                    Text(error).font(.footnote).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading)
                }
                if let state = repo.state {
                    if let id = cli, let p = state.providers.first(where: { $0.id == id }) {
                        CliDetailView(p: p, now: now)
                    } else {
                        switch which {
                        case .overview:
                            OverviewView(state: state, now: now, receivedAt: repo.receivedAt, openCli: { cli = $0 }, openTab: { tab = $0 })
                        case .clis:
                            CliListView(providers: state.providers, now: now) { cli = $0 }
                        case .mac:
                            SystemView(state: state, repo: repo)
                        case .tasks:
                            if let sea = state.sea {
                                TasksView(sea: sea, now: now, receivedAt: repo.receivedAt, repo: repo)
                            } else {
                                Text("A CLI sea não está configurada no Mac.").foregroundStyle(Palette.secondary)
                            }
                        }
                    }
                } else {
                    ProgressView().padding(.top, 80)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .refreshable { repo.act { try await $0.refresh(); return nil } }
        .background(Palette.background)
        .safeAreaInset(edge: .top, spacing: 0) { if let pairing = repo.pairing { header(pairing) } }
    }
}
