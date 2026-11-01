// Checks AgentStats.parse against the key shapes agent-exporter writes and Beszel stores.
// Run: scripts/check-agent-stats.sh [custom_stats.json]
import Foundation

var failures = 0
func expect(_ ok: Bool, _ message: String) {
    if !ok { print("FAIL: \(message)"); failures += 1 }
}

let sample: [String: Double] = [
    "agent_sessions_working": 2, "agent_sessions_waiting": 2, "agent_sessions_idle": 4,
    "agent_waiting_longest_seconds": 3798,
    "agent_waiting_session_seconds_dmarc_reports_mail": 3798,
    "agent_waiting_session_seconds_api_keys_gitignore": 22,
    "agent_processes_claude": 130, "agent_processes_codex": 1,
    "agent_memory_bytes_claude": 25_000_000_000, "agent_memory_bytes_codex": 100_000_000,
    "agent_stale_processes_claude": 103, "agent_stale_processes_codex": 0,
    "agent_stale_memory_bytes": 17_700_000_000,
    "agent_runaway_processes": 1, "agent_runaway_longest_seconds": 311_486,
    "ollama_up": 1, "ollama_models_loaded": 0,
]
if let s = AgentStats.parse(sample) {
    expect((s.working, s.waiting, s.idle) == (2, 2, 4), "session states \(s.working)/\(s.waiting)/\(s.idle)")
    expect(s.waitingSessions.map(\.name) == ["dmarc-reports-mail", "api-keys-gitignore"],
           "waiting names in longest-first order: \(s.waitingSessions.map(\.name))")
    expect(s.sessions == 131, "sessions summed across agents: \(s.sessions)")
    expect(s.stale == 103, "stale summed across agents: \(s.stale)")
    expect(s.sessionBytes == 25_100_000_000, "memory summed without stale memory: \(s.sessionBytes)")
    expect(s.runaway == 1 && s.runawayLongest == 311_486, "runaway")
    expect(s.ollamaUp == true && s.ollamaModels == 0, "ollama")
} else {
    expect(false, "parse returned nil for agent metrics")
}
expect(AgentStats.parse(["cpu_usage": 3]) == nil, "a row without agent series must be nil")
expect(AgentStats.duration(3798) == "1h 03m", "duration \(AgentStats.duration(3798))")
expect(AgentStats.duration(311_486) == "3d 14h", "duration \(AgentStats.duration(311_486))")

// Optional: a real custom_stats record saved from the hub.
if CommandLine.arguments.count > 1 {
    let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
    let record = try JSONDecoder().decode(CustomStatsRecord.self, from: data)
    if let s = AgentStats.parse(record.stats) {
        let written = record.stats.keys.filter { $0.hasPrefix(AgentStats.waitingPrefix) }.count
        expect(s.waitingSessions.count == written, "every waiting series becomes a row")
        expect(s.waiting >= s.waitingSessions.count, "waiting count \(s.waiting) below named rows")
        print("live record: \(s.sessions) sessions, \(s.waiting) waiting \(s.waitingSessions.map(\.name)), \(s.stale) stale")
    } else {
        expect(false, "live record has no agent series")
    }
}

if failures == 0 { print("ok") }
exit(failures == 0 ? 0 : 1)
