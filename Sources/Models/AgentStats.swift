import Foundation

/// One row of Beszel's `custom_stats` collection (henrygd/beszel#2562): a flat map of series key to value.
struct CustomStatsRecord: Codable {
    let id: String
    let system: String
    let stats: [String: Double]
    let created: String?
}

struct WaitingSession: Equatable, Identifiable {
    let name: String
    let seconds: Int
    var id: String { name }
}

/// Coding-agent metrics written by agent-exporter and stored by Beszel as custom metrics.
struct AgentStats: Equatable {
    var working = 0
    var waiting = 0
    var idle = 0
    var waitingSessions: [WaitingSession] = []
    var sessions = 0
    var sessionBytes = 0.0
    var stale = 0
    var staleBytes = 0.0
    var runaway = 0
    var runawayLongest = 0
    var ollamaUp: Bool?
    var ollamaModels: Int?

    static let waitingPrefix = "agent_waiting_session_seconds_"

    /// Returns nil when the record holds no agent-exporter series.
    static func parse(_ stats: [String: Double]) -> AgentStats? {
        guard stats.keys.contains(where: { $0.hasPrefix("agent_") }) else { return nil }
        var s = AgentStats()
        func int(_ key: String) -> Int { Int((stats[key] ?? 0).rounded()) }
        s.working = int("agent_sessions_working")
        s.waiting = int("agent_sessions_waiting")
        s.idle = int("agent_sessions_idle")
        s.staleBytes = stats["agent_stale_memory_bytes"] ?? 0
        s.runaway = int("agent_runaway_processes")
        s.runawayLongest = int("agent_runaway_longest_seconds")
        for (key, value) in stats {
            if key.hasPrefix(waitingPrefix) {
                // Beszel turns the session label into the key's tail, with "_" for separators.
                let name = String(key.dropFirst(waitingPrefix.count)).replacingOccurrences(of: "_", with: "-")
                s.waitingSessions.append(WaitingSession(name: name, seconds: Int(value.rounded())))
            } else if key.hasPrefix("agent_stale_processes_") {
                s.stale += Int(value.rounded())
            } else if key.hasPrefix("agent_processes_") {
                s.sessions += Int(value.rounded())
            } else if key.hasPrefix("agent_memory_bytes_") {
                s.sessionBytes += value
            }
        }
        s.waitingSessions.sort { ($0.seconds, $1.name) > ($1.seconds, $0.name) }
        if let up = stats["ollama_up"] {
            s.ollamaUp = up >= 1
            s.ollamaModels = stats["ollama_models_loaded"].map { Int($0.rounded()) }
        }
        return s
    }

    static func duration(_ seconds: Int) -> String {
        let s = max(0, seconds)
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86400 { return String(format: "%dh %02dm", s / 3600, (s % 3600) / 60) }
        return "\(s / 86400)d \((s % 86400) / 3600)h"
    }

    static func bytes(_ value: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(value))
    }
}
