import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var observationTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "server.rack", accessibilityDescription: "BeszelBar")
            button.image?.size = NSSize(width: 18, height: 18)
        }

        item.menu = MenuBuilder.build(appState: AppState.shared)
        self.statusItem = item

        LiveMetricsService.shared.onUpdate = { [weak self] in self?.redrawStatus() }
        AppState.shared.loadSystems()
        RefreshService.shared.start()
        startObserving()

        NSApp.setActivationPolicy(.accessory)
    }

    func applicationWillTerminate(_ notification: Notification) {
        RefreshService.shared.stop()
        LiveMetricsService.shared.stop()
        observationTask?.cancel()
    }

    private func startObserving() {
        observationTask = Task { @MainActor in
            while !Task.isCancelled {
                await withCheckedContinuation { continuation in
                    withObservationTracking {
                        _ = AppState.shared.instances
                        _ = AppState.shared.selectedInstance
                        _ = AppState.shared.selectedInstanceSystems
                        _ = AppState.shared.isLoading
                        _ = AppState.shared.activeAlerts
                        _ = AppState.shared.systemDetails
                        _ = AppState.shared.containers
                        _ = AppState.shared.agentStats
                        _ = AppState.shared.workHistory
                    } onChange: {
                        continuation.resume()
                    }
                }
                refreshMenu()
            }
        }
    }

    private func refreshMenu() {
        let appState = AppState.shared

        redrawStatus()
        statusItem?.menu = MenuBuilder.build(appState: appState)
    }

    /// Redraws only the menu bar item: live graphs when there are readings, else the plain icon.
    /// Runs every second while live data arrives, so it never rebuilds the menu.
    private func redrawStatus() {
        guard let button = statusItem?.button else { return }
        let appState = AppState.shared
        let alertCount = appState.activeAlerts.count
        let counts = appState.statusCounts
        let live = LiveMetricsService.shared.history
        // Servers first, then Macs, each group by name.
        let systems = appState.selectedInstanceSystems
            .filter { (live[$0.id]?.isEmpty == false) }
            .sorted { (isMac($0, appState) ? 1 : 0, $0.name) < (isMac($1, appState) ? 1 : 0, $1.name) }
        let graphs = systems.map { system -> StatusGraph in
            let points = live[system.id] ?? []
            return StatusGraph(label: system.name.lowercased(), cpu: points.map(\.cpu), mem: points.map(\.mem))
        }
        let work: [Double]? = counts == nil || appState.workHistory.isEmpty ? nil : appState.workHistory
        if graphs.isEmpty && counts == nil {
            button.image = NSImage(systemSymbolName: alertCount > 0 ? "server.rack.fill" : "server.rack",
                                   accessibilityDescription: "BeszelBar")
            button.image?.size = NSSize(width: 18, height: 18)
        } else {
            button.image = StatusImage.make(graphs, work: work, counts: counts, appearance: button.effectiveAppearance)
        }
        button.attributedTitle = StatusTitle.make(alerts: alertCount)
        var tip = systems.compactMap { system -> String? in
            guard let last = live[system.id]?.last else { return nil }
            return "\(system.name) CPU \(Int(last.cpu.rounded()))% RAM \(Int(last.mem.rounded()))%"
        }
        if let c = counts {
            tip.append("Needs you \(c.needsYou) · Your turn \(c.yourTurn) · Working \(c.working) · Stale \(c.stale)")
        }
        button.toolTip = tip.isEmpty ? nil : tip.joined(separator: "\n")
    }

    private func isMac(_ system: SystemRecord, _ appState: AppState) -> Bool {
        (appState.systemDetails[system.id]?.os ?? system.info?.os) == 1
    }
}
