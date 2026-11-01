import AppKit

/// The text beside the menu bar icon: the Beszel alert count, when there are alerts.
/// Agent session counts are drawn into the icon itself (StatusImage).
enum StatusTitle {
    static func make(alerts: Int) -> NSAttributedString {
        guard alerts > 0 else { return NSAttributedString() }
        return NSAttributedString(string: " \(alerts)", attributes: [.font: NSFont.menuBarFont(ofSize: 0)])
    }
}
