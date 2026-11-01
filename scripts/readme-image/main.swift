// Draws the README and social-preview images with the app's own drawing code and fixed sample
// data, so they can be rebuilt after any visual change. Run: scripts/render-readme-images.sh
import AppKit

func wave(_ base: Double, _ amp: Double, _ n: Int, _ f: Double, _ phase: Double = 0) -> [Double] {
    var out: [Double] = []
    for i in 0..<n {
        let swing: Double = amp * sin(Double(i) * f + phase)
        let jitter: Double = Double((i * 7) % 3)
        out.append(base + swing + jitter)
    }
    return out
}

let graphs = [
    StatusGraph(label: "box", cpu: wave(38, 20, 34, 0.5), mem: wave(86, 2, 34, 0.1), pressure: Array(repeating: 0, count: 34)),
    StatusGraph(label: "air", cpu: wave(16, 9, 34, 0.45, 1), mem: wave(70, 2, 34, 0.08),
                pressure: Array(repeating: 0, count: 22) + Array(repeating: 1, count: 12)),
]
let counts: [Double] = [2, 3, 2, 3, 3, 2, 3, 2, 4, 5, 4, 5, 5, 4, 6, 5, 4, 7, 6, 8, 7, 6, 7, 8, 7, 5, 6, 5, 4, 5, 5, 4, 5, 4]
let first = 29_892_048 + 4  // two columns into a 16-minute block, as a live graph usually is
var work: [WorkScale.Column] = []
for (i, c) in counts.enumerated() { work.append(WorkScale.Column(minute: first + 2 * i, count: c)) }
let item = StatusImage.make(graphs, work: work, counts: StatusCounts(working: 4, needsYou: 1, yourTurn: 18, stale: 104),
                            appearance: NSAppearance(named: .darkAqua)!)
let menuBar = NSColor(srgbRed: 0.13, green: 0.13, blue: 0.14, alpha: 1)

func save(_ image: NSImage, _ path: String) {
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

/// The menu bar item alone, magnified with hard pixel edges.
func strip(scale: CGFloat) -> NSImage {
    let size = NSSize(width: (item.size.width + 12) * scale, height: (item.size.height + 6) * scale)
    return NSImage(size: size, flipped: false) { r in
        menuBar.setFill(); NSBezierPath(roundedRect: r, xRadius: 3 * scale, yRadius: 3 * scale).fill()
        NSGraphicsContext.current?.imageInterpolation = .none
        item.draw(in: NSRect(x: 6 * scale, y: 3 * scale, width: item.size.width * scale, height: item.size.height * scale))
        return true
    }
}

/// 1280 x 640: title, one line of text, and the menu bar item.
func social(title: String, line: String) -> NSImage {
    let size = NSSize(width: 1280, height: 640)
    return NSImage(size: size, flipped: false) { r in
        NSColor(srgbRed: 0.07, green: 0.07, blue: 0.08, alpha: 1).setFill(); r.fill()
        let titleAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 76, weight: .bold), .foregroundColor: NSColor.white]
        let lineAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 34, weight: .regular),
                                                        .foregroundColor: NSColor(white: 0.72, alpha: 1)]
        (title as NSString).draw(at: NSPoint(x: 80, y: 470), withAttributes: titleAttrs)
        (line as NSString).draw(in: NSRect(x: 80, y: 350, width: 1120, height: 100), withAttributes: lineAttrs)
        let s = strip(scale: 7)
        s.draw(in: NSRect(x: (size.width - s.size.width) / 2, y: 70, width: s.size.width, height: s.size.height))
        return true
    }
}

let out = CommandLine.arguments[1]
save(strip(scale: 6), out + "/menu-bar.png")
save(social(title: "BeszelBar, agents fork",
            line: "Live pixel graphs for your servers and Macs, and the coding-agent sessions that need you."),
     out + "/social-beszelbar.png")
save(social(title: "agent-exporter",
            line: "Which of your coding agents need you? Claude Code, Codex, Gemini CLI and OpenCode, as Prometheus text."),
     out + "/social-agent-exporter.png")
