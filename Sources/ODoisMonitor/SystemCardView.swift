import SwiftUI

extension MemoryPressureLevel {
    /// Mesmas cores do gráfico de pressão do Monitor de Atividade.
    var color: Color {
        switch self {
        case .normal: return .green
        case .warning: return .yellow
        case .critical: return .red
        }
    }
}

enum Bytes {
    static func format(_ b: UInt64) -> String {
        let gb = Double(b) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f GB", gb).replacingOccurrences(of: ".", with: ",") }
        return "\(Int(Double(b) / 1_048_576)) MB"
    }
}

/// Card do item "Sistema": CPU, RAM, GPU, pressão de memória e processos das CLIs.
struct SystemCardView: View {
    @ObservedObject var monitor: SystemMonitor
    let names: [String: String]

    var body: some View {
        let s = monitor.current
        VStack(alignment: .leading, spacing: 14) {
            header(s)
            HStack(spacing: 0) {
                ring("CPU", s.cpu, .blue, detail: "\(ProcessInfo.processInfo.activeProcessorCount) núcleos")
                ring("RAM", s.ramTotal > 0 ? Double(s.ramUsed) / Double(s.ramTotal) : 0, .purple,
                     detail: "\(Bytes.format(s.ramUsed)) de \(Bytes.format(s.ramTotal))")
                ring("GPU", s.gpu ?? 0, .orange, detail: s.gpuMemory.map { Bytes.format($0) } ?? "—")
            }
            pressure(s)
            activity()
            processes()
        }
    }

    private func header(_ s: SystemSample) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(LinearGradient(colors: [.gray, .gray.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                .frame(width: 26, height: 26)
                .overlay(Image(systemName: "cpu").font(.system(size: 13, weight: .bold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 1) {
                Text("Sistema").font(.system(size: 14, weight: .semibold))
                Text("Atualiza a cada 2 s").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func ring(_ label: String, _ value: Double, _ color: Color, detail: String) -> some View {
        let v = min(max(value, 0), 1)
        return VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.1), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: v)
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.4), value: v)
                VStack(spacing: 0) {
                    Text("\(Int((v * 100).rounded()))%").font(.system(size: 14, weight: .bold, design: .rounded))
                    Text(label).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 62, height: 62)
            Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    /// Pressão de memória: nível atual e histórico colorido por nível.
    private func pressure(_ s: SystemSample) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("PRESSÃO DE MEMÓRIA").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Circle().fill(s.pressureLevel.color).frame(width: 7, height: 7)
                Text("\(s.pressureLevel.label) · \(Int((s.pressure * 100).rounded()))%")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(s.pressureLevel.color)
            }
            HistoryBars(
                values: monitor.history.map(\.pressure),
                colors: monitor.history.map { $0.pressureLevel.color },
                height: 34
            )
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                GridRow {
                    memoryLine("Comprimida", s.ramCompressed)
                    memoryLine("Residente", s.ramWired)
                }
                GridRow {
                    memoryLine("Em cache", s.ramCached)
                    memoryLine("Swap", s.swapUsed, of: s.swapTotal)
                }
            }
        }
    }

    private func memoryLine(_ label: String, _ value: UInt64, of total: UInt64? = nil) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(.secondary)
            Text(total.map { "\(Bytes.format(value)) de \(Bytes.format($0))" } ?? Bytes.format(value))
                .fontWeight(.semibold)
        }
        .font(.system(size: 10))
    }

    private func activity() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ÚLTIMOS 2 MIN").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                labeledBars("CPU", monitor.history.map(\.cpu), .blue)
                labeledBars("GPU", monitor.history.map { $0.gpu ?? 0 }, .orange)
            }
        }
    }

    private func labeledBars(_ label: String, _ values: [Double], _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            HistoryBars(values: values, colors: values.map { _ in color }, height: 22)
        }
    }

    @ViewBuilder
    private func processes() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PROCESSOS DAS CLIS").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            if monitor.processes.isEmpty {
                Text("Nenhuma CLI de LLM rodando agora.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            ForEach(monitor.processes) { p in
                HStack {
                    Text(names[p.id] ?? p.id).font(.system(size: 12, weight: .semibold))
                    Text("\(p.count) proc.").font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(p.cpu.rounded()))% CPU").font(.system(size: 11)).monospacedDigit()
                    Text(Bytes.format(p.memory))
                        .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                        .frame(width: 62, alignment: .trailing)
                }
            }
        }
    }
}

/// Barras verticais do histórico (valores de 0 a 1), alinhadas à direita.
struct HistoryBars: View {
    let values: [Double]
    let colors: [Color]
    let height: CGFloat

    var body: some View {
        GeometryReader { geo in
            let n = SystemMonitor.historySize
            let step = geo.size.width / CGFloat(n)
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06))
                ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                    let x = CGFloat(n - values.count + i) * step
                    Rectangle()
                        .fill(colors[i].opacity(0.85))
                        .frame(width: max(1, step - 1), height: max(1, height * CGFloat(min(max(v, 0), 1))))
                        .offset(x: x)
                }
            }
        }
        .frame(height: height)
    }
}
