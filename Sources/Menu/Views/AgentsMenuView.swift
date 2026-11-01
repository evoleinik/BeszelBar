import SwiftUI

/// Colours shared by the menu bar counts and the dropdown.
enum StatusColors {
    static let working = Color(nsColor: StatusImage.workingColor)
    static let needsYou = Color(nsColor: StatusImage.needsYouColor)
    static let yourTurn = Color(nsColor: StatusImage.yourTurnColor)
    static let stale = Color(nsColor: StatusImage.staleColor)
}

/// The Agents section: who needs you first, then the four statuses with what each one means.
struct AgentsMenuView: View {
    let systemName: String
    let stats: AgentStats

    static let rowHeight: CGFloat = 19
    static let captionHeight: CGFloat = 15

    static func height(for stats: AgentStats) -> CGFloat {
        var rows: CGFloat = 4 + 1  // four statuses and runaway
        if stats.ollamaUp != nil { rows += 1 }
        let captions: CGFloat = 3
        let needs = CGFloat(stats.needsYouSessions.count) * captionHeight
        return 30 + rows * rowHeight + captions * captionHeight + needs + 4
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Agents · \(systemName) · \(stats.total) sessions", systemImage: "terminal")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
            }
            .frame(height: 22)

            row("Needs you", "\(stats.needsYou)", dot: StatusColors.needsYou, emphasized: stats.needsYou > 0)
            ForEach(stats.needsYouSessions) { session in
                caption("\(session.name) · \(session.reason.text)", AgentStats.duration(session.seconds))
            }
            row("Working", "\(stats.working)", dot: StatusColors.working)
            caption("Mid-turn: thinking or running a tool")
            row("Your turn", "\(stats.yourTurn)", dot: StatusColors.yourTurn)
            caption("Finished, waiting for your next message")
            row("Stale", "\(stats.stale) · \(AgentStats.bytes(stats.staleBytes))", dot: StatusColors.stale)
            caption("Nothing for over a day; safe to close")
            row("Runaway processes",
                stats.runaway == 0 ? "none" : "\(stats.runaway) · \(AgentStats.duration(stats.runawayLongest))",
                dot: stats.runaway > 0 ? .red : nil)
            if let up = stats.ollamaUp {
                row("ollama", up ? "up, \(stats.ollamaModels ?? 0) models" : "down")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ title: String, _ value: String, dot: Color? = nil, emphasized: Bool = false) -> some View {
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
