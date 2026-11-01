import ActivityKit
import Foundation

/// Mantém uma Live Activity para o cronômetro de tarefa: começa quando há cronômetro,
/// atualiza ao pausar/retomar e termina quando ele é finalizado ou descartado.
@MainActor
enum LiveActivityController {
    private static var current: Activity<TimerActivityAttributes>? { Activity<TimerActivityAttributes>.activities.first }
    private static var taskId: Int?

    static func sync(_ timer: TaskTimer?, host: String, receivedAt: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard let timer else { return end() }
        let elapsed = timer.elapsed(at: Date(), receivedAt: receivedAt)
        let state = TimerActivityAttributes.ContentState(
            countingSince: timer.running ? Date().addingTimeInterval(-elapsed) : nil,
            pausedElapsed: elapsed,
            running: timer.running
        )
        if let activity = current, taskId == timer.task.id {
            // Só atualiza quando muda (rodando ↔ pausado); o relógio conta sozinho.
            if activity.content.state.running != state.running {
                Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
            }
            return
        }
        end()
        taskId = timer.task.id
        let attributes = TimerActivityAttributes(taskTitle: timer.task.title, projectName: timer.task.projectName, host: host)
        _ = try? Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: nil))
    }

    static func end() {
        taskId = nil
        for activity in Activity<TimerActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
