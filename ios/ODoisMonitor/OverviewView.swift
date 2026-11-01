import SwiftUI

struct OverviewView: View {
    let state: MonitorState
    let now: Date
    let receivedAt: Date
    var openCli: (String) -> Void
    var openTab: (AppTab) -> Void

    var body: some View {
        VStack(spacing: 14) {
            Card {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hoje").font(.subheadline).foregroundStyle(Palette.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(Fmt.tokens(state.todayTotal)).font(.system(size: 36, weight: .bold, design: .rounded)).contentTransition(.numericText())
                            Text("tokens").foregroundStyle(Palette.secondary)
                        }
                    }
                    Spacer()
                    let active = state.activeSessions ?? 0
                    Chip(text: active == 0 ? "nenhuma sessão ativa" : "\(active) \(active == 1 ? "sessão ativa" : "sessões ativas")",
                         color: active == 0 ? Palette.secondary : .green)
                }
                if let top = state.topLimit, top.limit.usedPercent >= 80 {
                    Label("\(top.provider.name): \(top.limit.label.lowercased()) em \(Int(top.limit.usedPercent))%", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.severity(top.limit.fraction))
                    if let eta = top.limit.forecastAt {
                        Text("No ritmo atual esgota \(Fmt.until(eta, now: now)) (\(Fmt.time(eta)))").font(.caption).foregroundStyle(.orange)
                    }
                }
            }

            if let t = state.sea?.running {
                Button { openTab(.tasks) } label: {
                    Card(gradient: Palette.hero) {
                        HStack {
                            Image(systemName: "timer")
                            VStack(alignment: .leading) {
                                Text(t.task.title).font(.headline).lineLimit(1)
                                Text(t.task.projectName).font(.caption).opacity(0.8).lineLimit(1)
                            }
                            Spacer()
                            Text(Fmt.clock(t.elapsed(at: now, receivedAt: receivedAt))).font(.system(size: 24, weight: .bold, design: .rounded)).monospacedDigit()
                        }
                        .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
            }

            Card {
                SectionTitle(title: "CLIs")
                let sorted = state.providers.sorted { ($0.topLimit?.usedPercent ?? 0, $0.isActive ? 1 : 0) > ($1.topLimit?.usedPercent ?? 0, $1.isActive ? 1 : 0) }
                ForEach(Array(sorted.enumerated()), id: \.element.id) { i, p in
                    if i > 0 { Divider().overlay(.white.opacity(0.08)) }
                    Button { openCli(p.id) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 12) {
                                ProviderIcon(provider: p, size: 30)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(p.name).font(.subheadline.weight(.semibold))
                                    Text(Fmt.activity(p.lastActivity, now: now)).font(.caption).foregroundStyle(p.isActive ? .green : Palette.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(Fmt.tokens(p.today.total)).font(.subheadline.weight(.semibold)).monospacedDigit()
                                    if let cost = p.costToday { Text(Fmt.usd(cost)).font(.caption2).foregroundStyle(.green) }
                                }
                            }
                            if let l = p.topLimit {
                                HStack(spacing: 8) {
                                    Meter(value: l.fraction, color: Palette.severity(l.fraction), height: 5)
                                    Text("\(l.label.lowercased()) \(Int(l.usedPercent))%").font(.caption2.weight(.semibold)).foregroundStyle(Palette.severity(l.fraction)).fixedSize()
                                }
                                .padding(.leading, 42)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Button { openTab(.mac) } label: {
                Card {
                    SectionTitle(title: "Mac · \(state.host ?? "Mac")", detail: "\(state.processes.count) processos de CLI")
                    let s = state.system
                    HStack(spacing: 16) {
                        gauge("CPU", s.cpu, .blue)
                        gauge("RAM", s.ramFraction, s.pressureLevel == "normal" ? .purple : Palette.pressure(s.pressureLevel))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Pressão").font(.caption).foregroundStyle(Palette.secondary)
                            HStack(spacing: 5) {
                                Circle().fill(Palette.pressure(s.pressureLevel)).frame(width: 7, height: 7)
                                Text(pressureLabel(s.pressureLevel)).font(.subheadline.weight(.semibold))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func gauge(_ label: String, _ value: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(label).font(.caption).foregroundStyle(Palette.secondary); Spacer(); Text(Fmt.percent(value)).font(.caption.weight(.semibold)) }
            Meter(value: value, color: color, height: 5)
        }
        .frame(maxWidth: .infinity)
    }
}

func pressureLabel(_ level: String) -> String {
    level == "critical" ? "Crítica" : level == "warning" ? "Atenção" : "Normal"
}
