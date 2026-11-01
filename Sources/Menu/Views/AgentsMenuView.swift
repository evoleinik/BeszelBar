import SwiftUI

/// The Agents section: who is waiting for you, then the rest of the agent state on one system.
struct AgentsMenuView: View {
    let systemName: String
    let stats: AgentStats

    static let rowHeight: CGFloat = 19

    static func height(for stats: AgentStats) -> CGFloat {
        var rows = 5  // working, idle, stale, runaway, sessions
        if stats.waiting > 0 { rows += 1 + stats.waitingSessions.count }
        if stats.ollamaUp != nil { rows += 1 }
        return 30 + CGFloat(rows) * rowHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Agents · \(systemName)", systemImage: "terminal")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
            }
            .frame(height: 22)

            if stats.waiting > 0 {
                row("Waiting for you", "\(stats.waiting)", tint: .orange, emphasized: true)
                ForEach(stats.waitingSessions) { session in
                    row(session.name, AgentStats.duration(session.seconds), indent: true)
                }
            }
            row("Working", "\(stats.working)")
            row("Idle", "\(stats.idle)")
            row("Stale over 1 day", "\(stats.stale) · \(AgentStats.bytes(stats.staleBytes))")
            row("Runaway processes",
                stats.runaway == 0 ? "none" : "\(stats.runaway) · \(AgentStats.duration(stats.runawayLongest))",
                tint: stats.runaway > 0 ? .red : nil)
            row("Agent sessions", "\(stats.sessions) · \(AgentStats.bytes(stats.sessionBytes))")
            if let up = stats.ollamaUp {
                row("ollama", up ? "up, \(stats.ollamaModels ?? 0) models" : "down")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ title: String, _ value: String, tint: Color? = nil, emphasized: Bool = false,
                     indent: Bool = false) -> some View {
        HStack(spacing: 6) {
            if let tint {
                Circle().fill(tint).frame(width: 6, height: 6)
            }
            Text(title)
                .foregroundColor(indent ? .secondary : .primary)
            Spacer()
            Text(value)
                .foregroundColor(indent ? .secondary : .primary)
                .monospacedDigit()
        }
        .font(.system(size: indent ? 11 : 12, weight: emphasized ? .semibold : .regular))
        .padding(.leading, indent ? 12 : 0)
        .padding(.horizontal, emphasized ? 6 : 0)
        .frame(height: Self.rowHeight)
        .background(emphasized ? (tint ?? .clear).opacity(0.15) : Color.clear)
        .cornerRadius(4)
        .padding(.horizontal, emphasized ? -6 : 0)
    }
}
