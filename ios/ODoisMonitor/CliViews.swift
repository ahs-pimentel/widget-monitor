import SwiftUI

struct CliListView: View {
    let providers: [Provider]
    let now: Date
    var open: (String) -> Void

    var body: some View {
        VStack(spacing: 12) {
            ForEach(providers) { p in
                Button { open(p.id) } label: {
                    Card {
                        HStack(spacing: 14) {
                            ProviderIcon(provider: p, size: 36, ring: p.topLimit?.fraction)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name).font(.headline)
                                Text(p.account ?? Fmt.activity(p.lastActivity, now: now)).font(.caption).foregroundStyle(Palette.secondary).lineLimit(1)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(Fmt.tokens(p.today.total)).font(.headline).monospacedDigit()
                                if let l = p.topLimit {
                                    Text("\(Int(l.usedPercent))% \(l.label.lowercased())").font(.caption2).foregroundStyle(Palette.severity(l.fraction))
                                } else {
                                    Text("hoje").font(.caption2).foregroundStyle(Palette.secondary)
                                }
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct CliDetailView: View {
    let p: Provider
    let now: Date

    private var tint: Color { Palette.hex(p.tint) }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                ProviderIcon(provider: p, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).font(.title2.bold())
                    if let account = p.account { Text(account).font(.caption).foregroundStyle(Palette.secondary).lineLimit(1) }
                    Text(Fmt.activity(p.lastActivity, now: now)).font(.caption).foregroundStyle(p.isActive ? .green : Palette.secondary)
                }
                Spacer()
                if let plan = p.plan { Chip(text: plan.uppercased(), color: Palette.secondary) }
            }

            if !p.limits.isEmpty || p.block != nil {
                Card {
                    ForEach(p.limits.sorted { $0.usedPercent > $1.usedPercent }, id: \.label) { l in
                        HStack(alignment: .firstTextBaseline) {
                            Text(l.label).font(.subheadline.weight(.medium))
                            Spacer()
                            Text("\(Int(l.usedPercent))%").font(.title3.bold()).foregroundStyle(Palette.severity(l.fraction))
                        }
                        Meter(value: l.fraction, color: Palette.severity(l.fraction), height: 8)
                        if let eta = l.forecastAt {
                            Label("No ritmo atual esgota \(Fmt.until(eta, now: now)) · \(Fmt.time(eta))", systemImage: "chart.line.uptrend.xyaxis")
                                .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                        }
                        if let reset = l.resetsAt { Text("Reinicia \(Fmt.until(reset, now: now)) · \(Fmt.time(reset))").font(.caption).foregroundStyle(Palette.secondary) }
                    }
                    if let b = p.block {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Bloco de 5 h").font(.subheadline.weight(.medium))
                            Text("estimado").font(.caption).foregroundStyle(Palette.secondary)
                            Spacer()
                            Text(Fmt.tokens(b.tokens)).font(.title3.bold())
                        }
                        Meter(value: 1 - max(0, b.endsAt.timeIntervalSince(now)) / (5 * 3600), color: tint, height: 8)
                        Text("Termina \(Fmt.until(b.endsAt, now: now)) · \(Fmt.time(b.endsAt))").font(.caption).foregroundStyle(Palette.secondary)
                    }
                }
            }

            Card {
                SectionTitle(title: "Hoje", detail: p.topModel)
                let t = p.today
                if t.total == 0 {
                    Text("Nenhum uso hoje").font(.title3.weight(.semibold)).foregroundStyle(Palette.secondary)
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        Text(Fmt.tokens(t.total)).font(.system(size: 32, weight: .bold, design: .rounded))
                        Text("tokens").foregroundStyle(Palette.secondary)
                        Spacer()
                        if let cost = p.costToday { Text(Fmt.usd(cost)).font(.headline).foregroundStyle(.green) }
                    }
                    Text("\(p.messagesToday ?? 0) respostas · \(p.sessionsToday ?? 0) \(p.sessionsToday == 1 ? "sessão" : "sessões")").font(.caption).foregroundStyle(Palette.secondary)
                    let parts: [(String, Int, Color)] = [("Entrada", t.input, .blue), ("Saída", t.output, .orange), ("Cache novo", t.cacheWrite, .cyan), ("Cache lido", t.cacheRead, .gray)]
                    let total = max(parts.reduce(0) { $0 + $1.1 }, 1)
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            ForEach(parts.filter { $0.1 > 0 }, id: \.0) { part in
                                Rectangle().fill(part.2).frame(width: max(3, (geo.size.width - 6) * CGFloat(part.1) / CGFloat(total)))
                            }
                        }
                        .clipShape(Capsule())
                    }
                    .frame(height: 10)
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                        ForEach(0..<2, id: \.self) { row in
                            GridRow {
                                ForEach(parts[(row * 2)..<(row * 2 + 2)], id: \.0) { part in
                                    HStack(spacing: 5) {
                                        Circle().fill(part.2).frame(width: 7, height: 7)
                                        Text(part.0).foregroundStyle(Palette.secondary)
                                        Spacer()
                                        Text(Fmt.tokens(part.1)).fontWeight(.semibold)
                                    }
                                    .font(.caption)
                                }
                            }
                        }
                    }
                }
            }

            Card {
                let daily = p.daily ?? []
                let avg = daily.reduce(0, +) / 7
                SectionTitle(title: "Últimos 7 dias", detail: "\(Fmt.tokens(p.weekTotal ?? 0)) · média \(Fmt.tokens(avg))/dia")
                let max = Double(daily.max() ?? 1).nonZero
                Bars(values: daily.map { Double($0) / max }, color: tint, highlightLast: true).frame(height: 70)
                HStack { ForEach(Array(Fmt.weekdays(now: now).enumerated()), id: \.offset) { i, d in
                    Text(d).font(.caption2.weight(i == 6 ? .bold : .regular)).foregroundStyle(i == 6 ? .primary : Palette.secondary).frame(maxWidth: .infinity)
                } }
            }

            if let history = p.history, history.count == 30, history.filter({ $0 > 0 }).count > 7 {
                Card {
                    let total = history.reduce(0, +)
                    SectionTitle(title: "30 dias", detail: "\(Fmt.tokens(total)) · média \(Fmt.tokens(total / 30))/dia")
                    let max = Double(history.max() ?? 1).nonZero
                    Bars(values: history.map { Double($0) / max }, color: tint, highlightLast: true).frame(height: 56)
                }
            }

            if let sessions = p.sessions, !sessions.isEmpty {
                Card {
                    SectionTitle(title: "Sessões recentes")
                    let max = Double(sessions.map(\.tokens).max() ?? 1).nonZero
                    ForEach(sessions) { s in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                if s.active == true { Circle().fill(.green).frame(width: 6, height: 6) }
                                Text(s.project ?? "Sessão \(s.id.prefix(6))").font(.subheadline.weight(.semibold)).lineLimit(1)
                                Spacer()
                                Text(Fmt.tokens(s.tokens)).font(.subheadline.weight(.semibold)).monospacedDigit()
                            }
                            Text([s.model, "\(s.messages) resp.", Fmt.relative(s.last, now: now)].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption2).foregroundStyle(Palette.secondary).lineLimit(1)
                            Meter(value: Double(s.tokens) / max, color: tint.opacity(0.8), height: 3)
                        }
                    }
                }
            }
            if let note = p.note { Text(note).font(.caption).foregroundStyle(Palette.secondary) }
        }
    }
}

extension Double {
    /// Evita divisão por zero nos gráficos.
    var nonZero: Double { self > 0 ? self : 1 }
}
