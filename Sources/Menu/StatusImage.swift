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

/// Session counts by status, summed across machines.
struct StatusCounts: Equatable {
    var working = 0
    var needsYou = 0
    var yourTurn = 0
    var stale = 0
    var values: [Int] { [working, needsYou, yourTurn, stale] }
}

/// One machine in the menu bar item: its name and its recent CPU and memory readings.
struct StatusGraph: Equatable {
    let label: String
    let cpu: [Double]
    let mem: [Double]
}

/// Draws the menu bar item: for each machine, its name turned like a book spine (reading bottom to
/// top) right against a graph with CPU and memory lines. Graphs are as tall as Stats draws its own.
enum StatusImage {
    /// Stats' graph height: the menu bar's thickness less a point above and below.
    static var height: CGFloat { max(16, NSStatusBar.system.thickness - 2) }
    static let graphWidth: CGFloat = 30
    static let labelFont = NSFont.systemFont(ofSize: 9, weight: .medium)
    static let labelGap: CGFloat = 1.5  // from the name's baseline to its graph
    static var labelWidth: CGFloat { (labelGap + labelFont.ascender).rounded(.up) }
    static let spacing: CGFloat = 6     // between one machine's graph and the next name
    static let workingColor = NSColor(srgbRed: 0.22, green: 0.54, blue: 0.87, alpha: 1)
    static let needsYouColor = NSColor(srgbRed: 0.94, green: 0.62, blue: 0.15, alpha: 1)
    static let yourTurnColor = NSColor(srgbRed: 0.39, green: 0.60, blue: 0.13, alpha: 1)
    static let staleColor = NSColor(srgbRed: 0.53, green: 0.53, blue: 0.50, alpha: 1)
    static let countFont = NSFont.monospacedDigitSystemFont(ofSize: 5.5, weight: .semibold)
    static let cpuColor = NSColor(srgbRed: 0.52, green: 0.72, blue: 0.92, alpha: 1)
    static let memColor = NSColor(srgbRed: 0.59, green: 0.77, blue: 0.35, alpha: 1)

    static func width(for count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * (labelWidth + graphWidth) + CGFloat(count - 1) * spacing
    }

    /// Width of the four stacked session counts: a dot, then the widest number.
    static func countsWidth(_ counts: StatusCounts) -> CGFloat {
        let widest = counts.values.map { NSAttributedString(string: "\($0)", attributes: [.font: countFont]).size().width }.max() ?? 0
        return 3 + 1.5 + widest.rounded(.up)
    }

    static func make(_ graphs: [StatusGraph], counts: StatusCounts?, appearance: NSAppearance) -> NSImage {
        let height = Self.height
        let graphsWidth = width(for: graphs.count)
        let countsGap: CGFloat = graphs.isEmpty ? 0 : spacing
        let total = graphsWidth + (counts.map { countsGap + countsWidth($0) } ?? 0)
        let image = NSImage(size: NSSize(width: total, height: height), flipped: false) { _ in
            appearance.performAsCurrentDrawingAppearance {
                var x: CGFloat = 0
                for graph in graphs {
                    let box = NSRect(x: x + labelWidth, y: 0, width: graphWidth, height: height)
                    drawLabel(graph.label, beside: box)
                    NSColor(white: 0.16, alpha: 1).setFill()
                    NSBezierPath(roundedRect: box, xRadius: 2, yRadius: 2).fill()
                    stroke(graph.mem, in: box, color: memColor)
                    stroke(graph.cpu, in: box, color: cpuColor)
                    x += labelWidth + graphWidth + spacing
                }
                if let counts {
                    drawCounts(counts, at: graphsWidth + countsGap, height: height)
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

    /// Four rows, top to bottom: working, needs you, your turn, stale. Each is a coloured dot and a count.
    private static func drawCounts(_ counts: StatusCounts, at x: CGFloat, height: CGFloat) {
        let rowHeight = height / 4
        let rows: [(Int, NSColor, NSColor)] = [
            (counts.working, workingColor, .labelColor),
            (counts.needsYou, needsYouColor, counts.needsYou > 0 ? needsYouColor : .secondaryLabelColor),
            (counts.yourTurn, yourTurnColor, .labelColor),
            (counts.stale, staleColor, .secondaryLabelColor),
        ]
        for (index, (value, dotColor, textColor)) in rows.enumerated() {
            let midY = height - (CGFloat(index) + 0.5) * rowHeight
            dotColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: midY - 1.3, width: 2.6, height: 2.6)).fill()
            let text = NSAttributedString(string: "\(value)", attributes: [.font: countFont, .foregroundColor: textColor])
            let size = text.size()
            text.draw(at: NSPoint(x: x + 3 + 1.5, y: midY - size.height / 2))
        }
    }

    /// The name turned a quarter turn anticlockwise, reading bottom to top, centred on the graph's
    /// height, with its baseline `labelGap` to the left of the graph.
    private static func drawLabel(_ text: String, beside box: NSRect) {
        guard !text.isEmpty else { return }
        var font = labelFont
        var string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
        while string.size().width > box.height - 2 && font.pointSize > 5 {
            font = NSFont.systemFont(ofSize: font.pointSize - 0.5, weight: .medium)
            string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
        }
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: box.minX, yBy: box.midY)
        transform.rotate(byDegrees: 90)
        transform.concat()
        // Rotated: +x runs up the graph's edge, +y runs left, away from the graph.
        // draw(at:) places the line's bottom (the descender) at y, so the baseline sits at y - descender.
        string.draw(at: NSPoint(x: -string.size().width / 2, y: labelGap + font.descender))
        NSGraphicsContext.restoreGraphicsState()
    }
}
