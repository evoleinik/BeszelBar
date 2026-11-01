import SwiftUI

/// Colours shared by the menu bar and the dropdown.
enum StatusColors {
    static let working = Color(nsColor: StatusImage.workColor)
    static let needsYou = Color(nsColor: StatusImage.needsYouColor)
    static let yourTurn = Color(nsColor: StatusImage.yourTurnColor)
    static let stale = Color(nsColor: StatusImage.staleColor)
}

/// The Agents section: who needs you, which of your turns have waited longest, then how busy the
/// agents are and how many sessions are stale. Hover a row for what its status means.
struct AgentsMenuView: View {
    let systemName: String
    let stats: AgentStats

    static let rowHeight: CGFloat = 19
    static let captionHeight: CGFloat = 15
    static let shownTurns = 5

    static func height(for stats: AgentStats) -> CGFloat {
        var rows: CGFloat = 5  // needs you, your turn, working, stale, runaway
        if stats.ollamaUp != nil { rows += 1 }
        var captions = CGFloat(stats.needsYouSessions.count + min(stats.yourTurnSessions.count, shownTurns))
        if stats.yourTurn > min(stats.yourTurnSessions.count, shownTurns) { captions += 1 }
        return 30 + rows * rowHeight + captions * captionHeight + 6
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Agents · \(systemName) · \(stats.total) sessions", systemImage: "terminal")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
            }
            .frame(height: 22)

            row("N · Needs you", "\(stats.needsYou)", dot: StatusColors.needsYou, emphasized: stats.needsYou > 0,
                help: "Blocked until you act: a permission, a question, a plan to approve, or input it asked for.")
            ForEach(stats.needsYouSessions) { session in
                caption("\(session.name) · \(session.reason.text)", AgentStats.duration(session.seconds))
            }
            row("T · Your turn", "\(stats.yourTurn)", dot: StatusColors.yourTurn,
                help: "Finished within a day and waiting for your next message. The oldest may need a push.")
            ForEach(stats.yourTurnSessions.prefix(Self.shownTurns)) { session in
                caption(session.name, AgentStats.duration(session.seconds))
            }
            if stats.yourTurn > min(stats.yourTurnSessions.count, Self.shownTurns) {
                caption("… \(stats.yourTurn - min(stats.yourTurnSessions.count, Self.shownTurns)) more, oldest first")
            }
            row("W · Working", "\(stats.working)", dot: StatusColors.working,
                help: "Mid-turn: thinking or running a tool. The work graph shows the last 68 minutes.")
            row("Stale, over a day", "\(stats.stale) · \(AgentStats.bytes(stats.staleBytes))", dot: StatusColors.stale,
                help: "No activity for over a day. Safe to close; the memory they hold is shown.")
            row("Runaway processes",
                stats.runaway == 0 ? "none" : "\(stats.runaway) · \(AgentStats.duration(stats.runawayLongest))",
                dot: stats.runaway > 0 ? .red : nil,
                help: "Processes an agent started that kept a CPU core busy for over an hour.")
            if let up = stats.ollamaUp {
                row("ollama", up ? "up, \(stats.ollamaModels ?? 0) models" : "down")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ title: String, _ value: String, dot: Color? = nil, emphasized: Bool = false,
                     help: String? = nil) -> some View {
        HStack(spacing: 6) {
            if let dot {
                Circle().fill(dot).frame(width: 6, height: 6)
            }
            Text(title)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.system(size: 12, weight: emphasized ? .semibold : .regular))
        .padding(.horizontal, emphasized ? 6 : 0)
        .frame(height: Self.rowHeight)
        .background(emphasized ? StatusColors.needsYou.opacity(0.15) : Color.clear)
        .cornerRadius(4)
        .padding(.horizontal, emphasized ? -6 : 0)
        .help(help ?? "")
    }

    private func caption(_ text: String, _ trailing: String? = nil) -> some View {
        HStack {
            Text(text).lineLimit(1).truncationMode(.middle)
            Spacer()
            if let trailing { Text(trailing).monospacedDigit() }
        }
        .font(.system(size: 11))
        .foregroundColor(.secondary)
        .padding(.leading, 12)
        .frame(height: Self.captionHeight)
    }
}
