// Checks AgentStats.parse against the key shapes agent-exporter writes and Beszel stores.
// Run: scripts/check-agent-stats.sh [custom_stats.json]
import Foundation

var failures = 0
func expect(_ ok: Bool, _ message: String) {
    if !ok { print("FAIL: \(message)"); failures += 1 }
}

let sample: [String: Double] = [
    "agent_sessions_working": 3, "agent_sessions_needs_you": 2, "agent_sessions_your_turn": 21,
    "agent_sessions_stale": 106, "agent_needs_you_longest_seconds": 3798,
    "agent_needs_you_session_seconds_input_dmarc_reports_mail": 3798,
    "agent_needs_you_session_seconds_question_api_keys_gitignore": 22,
    "agent_needs_you_session_seconds_bogus_x": 5,
    "agent_processes_claude": 131, "agent_processes_codex": 1,
    "agent_memory_bytes_claude": 25_000_000_000, "agent_memory_bytes_codex": 100_000_000,
    "agent_stale_memory_bytes": 17_700_000_000,
    "agent_runaway_processes": 1, "agent_runaway_longest_seconds": 311_486,
    "ollama_up": 1, "ollama_models_loaded": 0,
]
if let s = AgentStats.parse(sample) {
    expect((s.working, s.needsYou, s.yourTurn, s.stale) == (3, 2, 21, 106), "statuses")
    expect(s.total == 132 && s.sessions == 132, "four statuses sum to the sessions: \(s.total) vs \(s.sessions)")
    expect(s.needsYouSessions.map(\.name) == ["dmarc-reports-mail", "api-keys-gitignore"],
           "names longest first, unknown reasons dropped: \(s.needsYouSessions.map(\.name))")
    expect(s.needsYouSessions.map(\.reason) == [.input, .question], "reasons")
    expect(s.staleBytes == 17_700_000_000 && s.sessionBytes == 25_100_000_000, "memory")
    expect(s.runaway == 1 && s.runawayLongest == 311_486, "runaway")
    expect(s.ollamaUp == true && s.ollamaModels == 0, "ollama")
} else {
    expect(false, "parse returned nil for agent metrics")
}
expect(AgentStats.parse(["cpu_usage": 3]) == nil, "a row without agent series must be nil")
expect(AgentStats.duration(3798) == "1h 03m", "duration \(AgentStats.duration(3798))")

// Optional: a real custom_stats record saved from the hub.
if CommandLine.arguments.count > 1 {
    let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
    let record = try JSONDecoder().decode(CustomStatsRecord.self, from: data)
    if let s = AgentStats.parse(record.stats) {
        let written = record.stats.keys.filter { $0.hasPrefix(AgentStats.needsYouPrefix) }.count
        expect(s.needsYouSessions.count == written, "every needs-you series becomes a row")
        expect(s.total == s.sessions, "statuses \(s.total) sum to sessions \(s.sessions)")
        print("live record: \(s.working) working, \(s.needsYou) needs you \(s.needsYouSessions.map(\.name)), \(s.yourTurn) your turn, \(s.stale) stale")
    } else {
        expect(false, "live record has no agent series")
    }
}

if failures == 0 { print("ok") }
exit(failures == 0 ? 0 : 1)
