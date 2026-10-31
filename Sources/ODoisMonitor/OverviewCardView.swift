import SwiftUI

/// Visão geral: todas as CLIs e o sistema num só card, com o que pede atenção em destaque.
struct OverviewCardView: View {
    static let id = "overview"

    @ObservedObject var store: UsageStore
    @ObservedObject var monitor: SystemMonitor

    private var providers: [UsageStore.Item] {
        store.items.filter { $0.id != SystemProvider.identifier }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CardMetrics.spacing) {
            header
            VStack(spacing: 0) {
                ForEach(Array(sortedProviders.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().opacity(0.5) }
                    row(item)
                }
            }
            system
        }
    }

    /// CLIs com limite crítico primeiro, depois as em uso, depois o resto.
    private var sortedProviders: [UsageStore.Item] {
        let ranked = providers.enumerated().map { offset, item -> (Int, Int, UsageStore.Item) in
            let snap = store.snapshots[item.id]
            let rank = snap?.attention?.isWarning == true ? 0 : Activity.isActive(snap?.lastActivity) ? 1 : 2
            return (rank, offset, item)
        }
        return ranked.sorted { ($0.0, $0.1) < ($1.0, $1.1) }.map(\.2)
    }

    private var header: some View {
        let total = providers.reduce(0) { $0 + (store.snapshots[$1.id]?.today.total ?? 0) }
        let active = providers.filter { Activity.isActive(store.snapshots[$0.id]?.lastActivity) }.count
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("oDois Monitor").font(.system(size: 13, weight: .semibold))
                Text(active == 0 ? "Nenhuma CLI em uso agora" : "\(active) \(active == 1 ? "CLI em uso" : "CLIs em uso") agora")
                    .font(.system(size: 11))
                    .foregroundStyle(active == 0 ? Color.secondary : Color.green)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(Format.tokens(total))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("tokens hoje").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ item: UsageStore.Item) -> some View {
        let snap = store.snapshots[item.id]
        let attention = snap?.attention
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                ProviderIcon(item: item, size: 22, active: Activity.isActive(snap?.lastActivity))
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.provider.name).font(.system(size: 12, weight: .semibold))
                    Text(Activity.text(snap?.lastActivity))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(snap.map { Format.tokens($0.today.total) } ?? "—")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    if let cost = snap?.costToday {
                        Text(Format.usd(cost)).font(.system(size: 10)).foregroundStyle(.green)
                    }
                }
            }
            if let attention {
                HStack(spacing: 8) {
                    Meter(value: attention.value, color: attention.color, height: 5)
                    Text("\(attention.label.lowercased()) \(attention.percent)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(attention.color)
                        .fixedSize()
                }
                .padding(.leading, 32)
                .help(attention.resetsAt.map { "Reinicia \(Format.until($0)) · \(Format.time($0))" } ?? "")
            }
        }
        .padding(.vertical, 6)
    }

    private var system: some View {
        let s = monitor.current
        let procs = monitor.cliProcesses
        let background = procs.filter(\.background).count
        return VStack(alignment: .leading, spacing: 8) {
            systemGauges(s)
            if !procs.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "terminal").font(.system(size: 9))
                    Text("\(procs.count) \(procs.count == 1 ? "processo" : "processos") de CLI")
                    if background > 0 {
                        Text("· \(background) em 2º plano").foregroundStyle(.orange)
                    }
                    Spacer()
                    Text("ver em Sistema").foregroundStyle(.tertiary)
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
        }
        .modifier(InsetBox())
    }

    private func systemGauges(_ s: SystemSample) -> some View {
        HStack(spacing: 14) {
            gauge("CPU", s.cpu, .blue, "\(Int((s.cpu * 100).rounded()))%")
            gauge("RAM", s.ramFraction, s.attention.color == .green ? .purple : s.attention.color,
                  "\(Int((s.ramFraction * 100).rounded()))%")
                .help("\(Bytes.format(s.ramUsed)) de \(Bytes.format(s.ramTotal))")
            VStack(alignment: .leading, spacing: 3) {
                Text("Pressão").font(.system(size: 10)).foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Circle().fill(s.pressureLevel.color).frame(width: 6, height: 6)
                    Text(s.pressureLevel.label).font(.system(size: 11, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func gauge(_ label: String, _ value: Double, _ color: Color, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer(minLength: 2)
                Text(detail).font(.system(size: 10, weight: .semibold)).monospacedDigit().lineLimit(1)
            }
            Meter(value: value, color: color, height: 5)
        }
        .frame(maxWidth: .infinity)
    }
}
