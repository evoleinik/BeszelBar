import Foundation

/// One row of Beszel's `custom_stats` collection (henrygd/beszel#2562): a flat map of series key to value.
struct CustomStatsRecord: Codable {
    let id: String
    let system: String
    let stats: [String: Double]
    let created: String?
}

/// Why a session needs you, as agent-exporter labels it.
enum NeedsYouReason: String, CaseIterable {
    case permission, question, plan, input, form

    var text: String {
        switch self {
        case .permission: return "wants permission"
        case .question: return "asked a question"
        case .plan: return "wants a plan approved"
        case .input: return "needs your input"
        case .form: return "needs a form filled"
        }
    }
}

struct WaitingSession: Equatable, Identifiable {
    let name: String
    let reason: NeedsYouReason
    let seconds: Int
    var id: String { reason.rawValue + "/" + name }
}

/// Coding-agent metrics written by agent-exporter and stored by Beszel as custom metrics.
/// Every session is in exactly one status, so the four counts add up to all sessions.
struct AgentStats: Equatable {
    var working = 0
    var needsYou = 0
    var yourTurn = 0
    var stale = 0
    var needsYouSessions: [WaitingSession] = []
    var sessions = 0
    var sessionBytes = 0.0
    var staleBytes = 0.0
    var runaway = 0
    var runawayLongest = 0
    var ollamaUp: Bool?
    var ollamaModels: Int?

    var total: Int { working + needsYou + yourTurn + stale }

    static let needsYouPrefix = "agent_needs_you_session_seconds_"

    /// Returns nil when the record holds no agent-exporter series.
    static func parse(_ stats: [String: Double]) -> AgentStats? {
        guard stats.keys.contains(where: { $0.hasPrefix("agent_") }) else { return nil }
        var s = AgentStats()
        func int(_ key: String) -> Int { Int((stats[key] ?? 0).rounded()) }
        s.working = int("agent_sessions_working")
        s.needsYou = int("agent_sessions_needs_you")
        s.yourTurn = int("agent_sessions_your_turn")
        s.stale = int("agent_sessions_stale")
        s.staleBytes = stats["agent_stale_memory_bytes"] ?? 0
        s.runaway = int("agent_runaway_processes")
        s.runawayLongest = int("agent_runaway_longest_seconds")
        for (key, value) in stats {
            if key.hasPrefix(needsYouPrefix) {
                // Beszel builds the key from the label values in label-name order: reason, then
                // session, joined by "_" with other separators turned into "_".
                let tail = key.dropFirst(needsYouPrefix.count)
                guard let cut = tail.firstIndex(of: "_"),
                      let reason = NeedsYouReason(rawValue: String(tail[..<cut])) else { continue }
                let name = String(tail[tail.index(after: cut)...]).replacingOccurrences(of: "_", with: "-")
                s.needsYouSessions.append(WaitingSession(name: name, reason: reason, seconds: Int(value.rounded())))
            } else if key.hasPrefix("agent_processes_") {
                s.sessions += Int(value.rounded())
            } else if key.hasPrefix("agent_memory_bytes_") {
                s.sessionBytes += value
            }
        }
        s.needsYouSessions.sort { ($0.seconds, $1.name) > ($1.seconds, $0.name) }
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
