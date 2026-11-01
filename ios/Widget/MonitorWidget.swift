import ActivityKit
import SwiftUI
import WidgetKit

@main
struct MonitorWidgets: WidgetBundle {
    var body: some Widget {
        MonitorWidget()
        TimerLiveActivity()
    }
}

// MARK: - Widget da tela inicial e da tela bloqueada

struct MonitorEntry: TimelineEntry {
    let date: Date
    let state: MonitorState?
    let receivedAt: Date
}

struct MonitorProvider: TimelineProvider {
    func placeholder(in context: Context) -> MonitorEntry { MonitorEntry(date: Date(), state: nil, receivedAt: Date()) }

    func getSnapshot(in context: Context, completion: @escaping (MonitorEntry) -> Void) {
        let cached = SharedState.load()
        completion(MonitorEntry(date: Date(), state: cached?.state, receivedAt: cached?.receivedAt ?? Date()))
    }

    /// O app e o refresh em segundo plano gravam o estado no App Group e pedem recarga.
    func getTimeline(in context: Context, completion: @escaping (Timeline<MonitorEntry>) -> Void) {
        let cached = SharedState.load()
        let entry = MonitorEntry(date: Date(), state: cached?.state, receivedAt: cached?.receivedAt ?? Date())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

struct MonitorWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MonitorWidget", provider: MonitorProvider()) { entry in
            MonitorWidgetView(entry: entry)
                .containerBackground(for: .widget) { Palette.background }
                .widgetURL(URL(string: entry.state?.sea?.running != nil ? "odoismonitor://tab/tarefas" : "odoismonitor://tab/geral"))
        }
        .configurationDisplayName("oDois Monitor")
        .description("Tokens de hoje, o limite mais alto e o cronômetro da tarefa.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}

struct MonitorWidgetView: View {
    let entry: MonitorEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let state = entry.state {
            switch family {
            case .accessoryCircular: circular(state)
            case .accessoryRectangular: rectangular(state)
            default: home(state)
            }
        } else {
            VStack(alignment: .leading) {
                Text("oDois Monitor").font(.caption.bold())
                Text("Abra o app para parear").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func home(_ state: MonitorState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("oDois · \(state.host ?? "Mac")").font(.caption2).foregroundStyle(Palette.secondary).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Fmt.tokens(state.todayTotal)).font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(.white)
                Text("hoje").font(.caption2).foregroundStyle(Palette.secondary)
            }
            if let top = state.topLimit {
                Text("\(top.provider.name) · \(Int(top.limit.usedPercent))%").font(.caption2.weight(.semibold)).foregroundStyle(Palette.severity(top.limit.fraction)).lineLimit(1)
                ProgressView(value: top.limit.fraction).tint(Palette.severity(top.limit.fraction))
            }
            Spacer(minLength: 0)
            if let t = state.sea?.running {
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                    Text(timerInterval: Date().addingTimeInterval(-t.elapsed(at: Date(), receivedAt: entry.receivedAt))...Date.distantFuture, countsDown: false)
                        .font(.caption.bold()).monospacedDigit()
                    if family == .systemMedium { Text(t.task.title).font(.caption2).lineLimit(1) }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Capsule().fill(Palette.hero))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func rectangular(_ state: MonitorState) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let t = state.sea?.running {
                Label { Text(timerInterval: Date().addingTimeInterval(-t.elapsed(at: Date(), receivedAt: entry.receivedAt))...Date.distantFuture, countsDown: false).monospacedDigit() } icon: { Image(systemName: "timer") }
                Text(t.task.title).font(.caption2).lineLimit(1)
            } else {
                Text("\(Fmt.tokens(state.todayTotal)) tokens hoje").font(.headline)
            }
            if let top = state.topLimit {
                Text("\(top.provider.name) \(Int(top.limit.usedPercent))%").font(.caption2)
            }
        }
    }

    private func circular(_ state: MonitorState) -> some View {
        let fraction = state.topLimit?.limit.fraction ?? 0
        return Gauge(value: fraction) { Text("lim") } currentValueLabel: { Text("\(Int(fraction * 100))") }
            .gaugeStyle(.accessoryCircular)
    }
}

// MARK: - Live Activity do cronômetro

struct TimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            // Tela bloqueada e banner.
            HStack(spacing: 12) {
                Image(systemName: context.state.running ? "timer" : "pause.circle.fill").font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.taskTitle).font(.headline).lineLimit(1)
                    Text("\(context.attributes.projectName) · \(context.attributes.host)").font(.caption).opacity(0.8).lineLimit(1)
                }
                Spacer()
                clock(context.state).font(.system(size: 28, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(16)
            .activityBackgroundTint(Palette.indigo)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("oDois", systemImage: context.state.running ? "timer" : "pause.fill").font(.caption.bold()).foregroundStyle(Palette.teal)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    clock(context.state).font(.title3.bold()).foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.taskTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(context.attributes.projectName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: context.state.running ? "timer" : "pause.fill").foregroundStyle(Palette.teal)
            } compactTrailing: {
                clock(context.state).font(.caption.bold()).frame(maxWidth: 56)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(Palette.teal)
            }
            .keylineTint(Palette.teal)
        }
    }

    @ViewBuilder
    private func clock(_ state: TimerActivityAttributes.ContentState) -> some View {
        if let since = state.countingSince, state.running {
            Text(timerInterval: since...Date.distantFuture, countsDown: false).monospacedDigit().multilineTextAlignment(.trailing)
        } else {
            Text(Fmt.clock(state.pausedElapsed)).monospacedDigit()
        }
    }
}
