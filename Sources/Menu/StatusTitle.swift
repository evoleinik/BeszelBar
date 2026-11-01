import AppKit

/// The text beside the menu bar icon: the alert count, then an amber dot and the number of
/// agent sessions waiting for you. Nothing shows when both are zero.
enum StatusTitle {
    static func make(alerts: Int, waiting: Int) -> NSAttributedString {
        let title = NSMutableAttributedString()
        let font = NSFont.menuBarFont(ofSize: 0)
        if alerts > 0 {
            title.append(NSAttributedString(string: " \(alerts)", attributes: [.font: font]))
        }
        if waiting > 0 {
            title.append(NSAttributedString(string: " ●", attributes: [
                .font: NSFont.systemFont(ofSize: 9),
                .foregroundColor: NSColor.systemOrange,
                .baselineOffset: 1.5,
            ]))
            title.append(NSAttributedString(string: "\u{2009}\(waiting)", attributes: [.font: font]))
        }
        return title
    }
}
