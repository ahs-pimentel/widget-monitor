import SwiftUI

final class CardSelection: ObservableObject {
    @Published var id: String?
}

struct UsageCardView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var selection: CardSelection

    /// Embutido no notch: sem vidro nem margem própria, o fundo é do notch.
    var embedded = false

    static let width: CGFloat = 300

    var body: some View {
        let inner = Group {
            if selection.id == SystemProvider.identifier {
                SystemCardView(
                    monitor: .shared,
                    names: Dictionary(uniqueKeysWithValues: store.items.map { ($0.id, $0.provider.name) })
                )
                .padding(embedded ? 4 : 16)
            } else if let id = selection.id, let item = store.items.first(where: { $0.id == id }) {
                content(item: item, snap: store.snapshots[id])
            }
        }
        .frame(width: Self.width)

        if embedded {
            inner
        } else {
            inner
                .modifier(GlassCard())
                .padding(BarMetrics.inset)
        }
    }

    @ViewBuilder
    private func content(item: UsageStore.Item, snap: UsageSnapshot?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            header(item: item)
            if let snap {
                hero(snap)
                breakdown(snap.today)
                limits(snap)
                week(snap, tint: Color(nsColor: item.provider.tint))
                sessions(snap, tint: Color(nsColor: item.provider.tint))
                footer(snap)
            } else {
                HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                    .padding(.vertical, 30)
            }
        }
        .padding(embedded ? 4 : 16)
    }

    private func header(item: UsageStore.Item) -> some View {
        HStack(spacing: 10) {
            ProviderIcon(item: item, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.provider.name).font(.system(size: 14, weight: .semibold))
                Text([store.snapshots[item.id]?.source, statusText(item.id)].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if let plan = store.snapshots[item.id]?.plan {
                Text(plan.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.1)))
            }
        }
    }

    private func statusText(_ id: String) -> String {
        if store.loading.contains(id) { return "Atualizando…" }
        guard let at = store.updatedAt[id] else { return "Carregando…" }
        return "Atualizado \(Format.relative(at))"
    }

    private func hero(_ snap: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("HOJE").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            Text(Format.tokens(snap.today.total) + " tokens")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            Text("\(snap.messagesToday) respostas · \(snap.sessionsToday) sessões")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            if let today = snap.costToday, let week = snap.costWeek {
                HStack(spacing: 6) {
                    Image(systemName: "dollarsign.circle").foregroundStyle(.green)
                    Text("\(Format.usd(today)) hoje")
                        .font(.system(size: 12, weight: .semibold))
                    Text("· \(Format.usd(week)) em 7 dias")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
        }
    }

    private func breakdown(_ t: TokenTotals) -> some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                metric("Entrada", t.input, "arrow.down.circle")
                metric("Saída", t.output, "arrow.up.circle")
            }
            GridRow {
                metric("Cache lido", t.cacheRead, "memorychip")
                metric("Cache gravado", t.cacheWrite, "square.and.arrow.down")
            }
        }
    }

    private func metric(_ label: String, _ value: Int, _ symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
                Text(Format.tokens(value)).font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
    }

    @ViewBuilder
    private func limits(_ snap: UsageSnapshot) -> some View {
        if !snap.limits.isEmpty || snap.blockEndsAt != nil {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(snap.limits) { limit in
                    limitBar(limit)
                }
                if let tokens = snap.blockTokens, let end = snap.blockEndsAt {
                    HStack {
                        Label("Bloco de 5 h (estimado)", systemImage: "clock")
                            .font(.system(size: 11))
                        Spacer()
                        Text(Format.tokens(tokens)).font(.system(size: 11, weight: .semibold))
                    }
                    Text("Termina às \(Format.time(end)) · \(Format.until(end))")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func limitBar(_ limit: RateLimit) -> some View {
        let pct = min(max(limit.usedPercent, 0), 100)
        let color: Color = pct >= 90 ? .red : pct >= 70 ? .orange : .green
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(limit.label).font(.system(size: 11))
                Spacer()
                Text("\(Int(pct.rounded()))% usado").font(.system(size: 11, weight: .semibold)).foregroundStyle(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.1))
                    Capsule().fill(color).frame(width: geo.size.width * pct / 100)
                }
            }
            .frame(height: 6)
            if let reset = limit.resetsAt {
                Text("Reinicia \(Format.until(reset)) (\(Format.time(reset)))")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    private func week(_ snap: UsageSnapshot, tint: Color) -> some View {
        let maxValue = max(snap.daily.max() ?? 0, 1)
        let labels = Format.weekdayInitials()
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("ÚLTIMOS 7 DIAS").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(Format.tokens(snap.week.total)).font(.system(size: 11, weight: .semibold))
            }
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(i == 6 ? tint : tint.opacity(0.45))
                            .frame(height: max(3, 44 * CGFloat(snap.daily[i]) / CGFloat(maxValue)))
                            .help(Format.tokens(snap.daily[i]))
                        Text(labels[i]).font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 58, alignment: .bottom)
        }
    }

    /// Quantas sessões o card lista (as mais recentes).
    static let sessionLimit = 3

    @ViewBuilder
    private func sessions(_ snap: UsageSnapshot, tint: Color) -> some View {
        if !snap.sessions.isEmpty {
            let shown = Array(snap.sessions.prefix(Self.sessionLimit))
            let maxTokens = max(shown.map(\.tokens.total).max() ?? 1, 1)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("SESSÕES RECENTES").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(snap.sessions.count) em 7 dias").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                ForEach(shown) { session in
                    sessionRow(session, share: Double(session.tokens.total) / Double(maxTokens), tint: tint)
                }
            }
        }
    }

    private func sessionRow(_ s: SessionUsage, share: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(s.project ?? "Sessão \(s.id.prefix(6))")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text(Format.tokens(s.tokens.total))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            HStack(alignment: .firstTextBaseline) {
                Text([s.model, "\(s.messages) resp.", Format.relative(s.last)].compactMap { $0 }.joined(separator: " · "))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                if s.cost > 0 { Text(Format.usd(s.cost)).foregroundStyle(.green) }
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            GeometryReader { geo in
                Capsule().fill(tint.opacity(0.7)).frame(width: max(3, geo.size.width * share))
            }
            .frame(height: 3)
        }
        .help("Entrada \(Format.tokens(s.tokens.input)) · Saída \(Format.tokens(s.tokens.output)) · Cache lido \(Format.tokens(s.tokens.cacheRead)) · Cache gravado \(Format.tokens(s.tokens.cacheWrite))")
    }

    @ViewBuilder
    private func footer(_ snap: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let model = snap.topModel {
                Label("Modelo mais usado hoje: \(model)", systemImage: "cpu")
            }
            if let last = snap.lastActivity {
                Label("Última atividade \(Format.relative(last))", systemImage: "bolt")
            }
            if let note = snap.note {
                Label(note, systemImage: "info.circle")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .lineLimit(2)
    }
}
