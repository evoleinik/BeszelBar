import AppKit

enum Sparkline {
    /// Points for a graph of `width` by `height`, `capacity` readings wide, newest at the right edge.
    /// Values are percentages; y starts at the bottom, as in an unflipped AppKit context.
    static func points(_ values: [Double], width: CGFloat, height: CGFloat, capacity: Int) -> [CGPoint] {
        guard !values.isEmpty, capacity > 1 else { return [] }
        let step = width / CGFloat(capacity - 1)
        let shown = Array(values.suffix(capacity))
        let start = CGFloat(capacity - shown.count) * step
        return shown.enumerated().map { index, value in
            let clamped = CGFloat(min(max(value, 0), 100))
            return CGPoint(x: start + CGFloat(index) * step, y: 1 + clamped / 100 * (height - 2))
        }
    }
}

/// One machine in the menu bar item: its symbol and its recent CPU and memory readings.
struct StatusGraph: Equatable {
    let symbol: String
    let cpu: [Double]
    let mem: [Double]
}

/// Draws the menu bar item: for each machine, its symbol and a small graph with CPU and memory lines.
enum StatusImage {
    static let height: CGFloat = 16
    static let graphWidth: CGFloat = 40
    static let symbolWidth: CGFloat = 16
    static let cpuColor = NSColor(srgbRed: 0.52, green: 0.72, blue: 0.92, alpha: 1)
    static let memColor = NSColor(srgbRed: 0.59, green: 0.77, blue: 0.35, alpha: 1)

    static func width(for count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * (symbolWidth + 3 + graphWidth) + CGFloat(count - 1) * 6
    }

    static func make(_ graphs: [StatusGraph], appearance: NSAppearance) -> NSImage {
        let image = NSImage(size: NSSize(width: width(for: graphs.count), height: height), flipped: false) { _ in
            appearance.performAsCurrentDrawingAppearance {
                var x: CGFloat = 0
                for graph in graphs {
                    drawSymbol(graph.symbol, in: NSRect(x: x, y: 0, width: symbolWidth, height: height))
                    let box = NSRect(x: x + symbolWidth + 3, y: 0, width: graphWidth, height: height)
                    NSColor(white: 0.16, alpha: 1).setFill()
                    NSBezierPath(roundedRect: box, xRadius: 2, yRadius: 2).fill()
                    stroke(graph.mem, in: box, color: memColor)
                    stroke(graph.cpu, in: box, color: cpuColor)
                    x += symbolWidth + 3 + graphWidth + 6
                }
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func stroke(_ values: [Double], in box: NSRect, color: NSColor) {
        let points = Sparkline.points(values, width: box.width, height: box.height, capacity: LiveMetricsService.capacity)
        guard points.count > 1 else { return }
        let path = NSBezierPath()
        path.lineWidth = 1.2
        path.lineJoinStyle = .round
        path.move(to: NSPoint(x: box.minX + points[0].x, y: box.minY + points[0].y))
        for point in points.dropFirst() {
            path.line(to: NSPoint(x: box.minX + point.x, y: box.minY + point.y))
        }
        color.setStroke()
        path.stroke()
    }

    private static func drawSymbol(_ name: String, in rect: NSRect) {
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .regular)) else { return }
        let size = symbol.size
        let tinted = NSImage(size: size, flipped: false) { bounds in
            symbol.draw(in: bounds)
            NSColor.labelColor.set()
            bounds.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                               width: size.width, height: size.height))
    }
}
