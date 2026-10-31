import SwiftUI

final class CardSelection: ObservableObject {
    @Published var id: String?
}

/// Card mostrado ao passar o mouse: visão geral, Sistema ou o detalhe de uma CLI.
struct UsageCardView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var selection: CardSelection

    /// Embutido no notch: sem vidro nem margem própria, o fundo é do notch.
    var embedded = false

    static let width = CardMetrics.width

    var body: some View {
        let inner = Group {
            if selection.id == OverviewCardView.id {
                OverviewCardView(store: store, monitor: .shared)
            } else if selection.id == SeaProvider.identifier {
                SeaTasksCardView(sea: .shared, showHeaderIcon: !embedded)
            } else if selection.id == SystemProvider.identifier {
                SystemCardView(
                    monitor: .shared,
                    names: Dictionary(uniqueKeysWithValues: store.items.map { ($0.id, $0.provider.name) })
                )
            } else if let id = selection.id, let item = store.items.first(where: { $0.id == id }) {
                ProviderCardView(
                    item: item,
                    snap: store.snapshots[id],
                    loading: store.loading.contains(id),
                    showHeaderIcon: !embedded
                )
            }
        }
        .padding(CardMetrics.padding)
        .frame(width: Self.width)

        if embedded {
            inner
        } else {
            inner
                .modifier(GlassCard())
                .padding(BarMetrics.inset)
        }
    }
}

/// Detalhe de uma CLI. Ordem pensada pela pergunta que o usuário traz:
/// 1) estou perto do limite? 2) quanto usei hoje? 3) como foi a semana? 4) onde gastei?
struct ProviderCardView: View {
    let item: UsageStore.Item
    let snap: UsageSnapshot?
    let loading: Bool
    /// No notch a aba selecionada já mostra o ícone; não repete no cabeçalho.
    var showHeaderIcon = true

    private var tint: Color { Color(nsColor: item.provider.tint) }

    var body: some View {
        VStack(alignment: .leading, spacing: CardMetrics.spacing) {
            header
            if let snap {
                limits(snap)
                today(snap)
                week(snap)
                sessions(snap)
                if let note = snap.note {
                    Label(note, systemImage: "info.circle")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                    .padding(.vertical, 30)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if showHeaderIcon { ProviderIcon(item: item, size: 24) }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.provider.name).font(.system(size: 13, weight: .semibold))
                HStack(spacing: 6) {
                    ActivityLabel(last: snap?.lastActivity)
                    if loading { ProgressView().controlSize(.mini) }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let plan = snap?.plan { Badge(text: plan) }
                if let source = snap?.source {
                    Text(source).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Limites

    @ViewBuilder
    private func limits(_ snap: UsageSnapshot) -> some View {
        let rows = snap.limits
            .map { Attention(value: $0.usedPercent / 100, label: $0.label, resetsAt: $0.resetsAt) }
            .sorted { $0.value > $1.value }
        if !rows.isEmpty || snap.blockEndsAt != nil {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(rows, id: \.label) { LimitRow(attention: $0) }
                if let tokens = snap.blockTokens, let end = snap.blockEndsAt {
                    block(tokens: tokens, end: end)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(InsetBox())
        }
    }

    /// Bloco de 5 h do Claude: o limite real não é gravado, então mostra o tempo do bloco.
    private func block(tokens: Int, end: Date) -> some View {
        let window: TimeInterval = 5 * 3600
        let elapsed = 1 - max(0, end.timeIntervalSinceNow) / window
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text("Bloco de 5 h").font(.system(size: 12, weight: .medium))
                Text("estimado").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Text(Format.tokens(tokens))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            Meter(value: elapsed, color: tint, height: 7)
            Text("Termina \(Format.until(end)) · \(Format.time(end))")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    // MARK: - Hoje

    @ViewBuilder
    private func today(_ snap: UsageSnapshot) -> some View {
        let t = snap.today
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle("Hoje", detail: snap.topModel)
            if t.total == 0 {
                Text("Nenhum uso hoje")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Format.tokens(t.total))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("tokens").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    Spacer()
                    if let cost = snap.costToday {
                        Text(Format.usd(cost))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.green)
                    }
                }
                Text("\(snap.messagesToday) respostas · \(snap.sessionsToday) \(snap.sessionsToday == 1 ? "sessão" : "sessões")")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                SegmentBar(segments: [
                    Segment(label: "Entrada", value: t.input, color: .blue),
                    Segment(label: "Saída", value: t.output, color: .orange),
                    Segment(label: "Cache novo", value: t.cacheWrite, color: .teal),
                    Segment(label: "Cache lido", value: t.cacheRead, color: .gray.opacity(0.55)),
                ])
            }
        }
    }

    // MARK: - Semana

    private func week(_ snap: UsageSnapshot) -> some View {
        let maxValue = max(snap.daily.max() ?? 0, 1)
        let labels = Format.weekdayInitials()
        let average = snap.daily.reduce(0, +) / 7
        let detail = Format.tokens(snap.week.total) + " · média " + Format.tokens(average) + "/dia"
            + (snap.costWeek.map { " · " + Format.usd($0) } ?? "")
        return VStack(alignment: .leading, spacing: 6) {
            SectionTitle("Últimos 7 dias", detail: detail)
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(0..<7, id: \.self) { i in
                    let isToday = i == 6
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(isToday ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(tint.opacity(0.35)))
                            .frame(height: max(3, 30 * CGFloat(snap.daily[i]) / CGFloat(maxValue)))
                            .help("\(labels[i]): \(Format.tokens(snap.daily[i]))")
                        Text(labels[i])
                            .font(.system(size: 9, weight: isToday ? .bold : .regular))
                            .foregroundStyle(isToday ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 44, alignment: .bottom)
        }
    }

    // MARK: - Sessões

    /// Quantas sessões o card lista (as mais recentes).
    static let sessionLimit = 3

    /// Recolhida por padrão; a escolha vale para todas as CLIs e também muda pelo menu.
    @AppStorage(Self.sessionsKey) private var sessionsExpanded = false
    static let sessionsKey = "sessionsExpanded"

    @ViewBuilder
    private func sessions(_ snap: UsageSnapshot) -> some View {
        if !snap.sessions.isEmpty {
            let shown = Array(snap.sessions.prefix(Self.sessionLimit))
            let maxTokens = max(shown.map(\.tokens.total).max() ?? 1, 1)
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { sessionsExpanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        SectionTitle("Sessões recentes", detail: "\(snap.sessions.count) em 7 dias")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(sessionsExpanded ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if sessionsExpanded {
                    ForEach(shown) { session in
                        sessionRow(session, share: Double(session.tokens.total) / Double(maxTokens))
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    private func sessionRow(_ s: SessionUsage, share: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                if Activity.isActive(s.last) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                }
                Text(Format.project(s.project) ?? "Sessão \(s.id.prefix(6))")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
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
            Meter(value: share, color: tint.opacity(0.8), height: 3)
        }
        .help("Entrada \(Format.tokens(s.tokens.input)) · Saída \(Format.tokens(s.tokens.output)) · Cache lido \(Format.tokens(s.tokens.cacheRead)) · Cache gravado \(Format.tokens(s.tokens.cacheWrite))")
    }
}
