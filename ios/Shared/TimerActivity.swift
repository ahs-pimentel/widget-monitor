import ActivityKit
import Foundation

/// Live Activity do cronômetro de tarefa (Dynamic Island e tela bloqueada).
/// O relógio usa `Text(timerInterval:)`, que conta sozinho sem atualizações.
struct TimerActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Início "virtual" do cronômetro (agora menos o tempo acumulado); nil quando pausado.
        var countingSince: Date?
        /// Tempo acumulado quando pausado.
        var pausedElapsed: Double
        var running: Bool
    }

    let taskTitle: String
    let projectName: String
    let host: String
}
