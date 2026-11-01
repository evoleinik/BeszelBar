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

/// Scales working-session counts to the graph: the top is at least 5 sessions, or the hour's peak.
enum WorkScale {
    /// The graph's top, in sessions: at least 5, or the hour's peak rounded up.
    static func top(_ counts: [Double]) -> Int { max(5, Int((counts.max() ?? 0).rounded(.up))) }

    struct Summary: Equatable {
        let max: Int
        let median: Int
        let now: Int
    }

    /// The hour's peak, median and latest working-session counts.
    static func summary(_ counts: [Double]) -> Summary {
        let sorted = counts.sorted()
        guard let last = counts.last, !sorted.isEmpty else { return Summary(max: 0, median: 0, now: 0) }
        let mid = sorted.count / 2
        let median = sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
        return Summary(max: Int(sorted.last!.rounded()), median: Int(median.rounded()), now: Int(last.rounded()))
    }

    static func percent(_ counts: [Double]) -> [Double] {
        let t = Double(top(counts))
        return counts.map { $0 / t * 100 }
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
    static let spacing: CGFloat = 3     // between one graph and the next name
    static let workingColor = NSColor(srgbRed: 0.22, green: 0.54, blue: 0.87, alpha: 1)
    static let needsYouColor = NSColor(srgbRed: 0.94, green: 0.62, blue: 0.15, alpha: 1)
    static let yourTurnColor = NSColor(srgbRed: 0.39, green: 0.60, blue: 0.13, alpha: 1)
    static let staleColor = NSColor(srgbRed: 0.53, green: 0.53, blue: 0.50, alpha: 1)
    static let workColor = NSColor(srgbRed: 0.50, green: 0.47, blue: 0.87, alpha: 1)
    static let bigFont = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
    static let letterFont = NSFont.systemFont(ofSize: 9, weight: .semibold)
    static let scaleFont = NSFont.monospacedDigitSystemFont(ofSize: 6.5, weight: .semibold)
    static let workCapacity = 60  // one point per minute: the last hour
    static let cpuColor = NSColor(srgbRed: 0.52, green: 0.72, blue: 0.92, alpha: 1)
    static let memColor = NSColor(srgbRed: 0.59, green: 0.77, blue: 0.35, alpha: 1)

    static func width(for count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * (labelWidth + graphWidth) + CGFloat(count - 1) * spacing
    }

    /// "1N" and "18T": the two counts that ask something of you. N sits in an amber pill above zero.
    static func attention(_ counts: StatusCounts) -> [(NSAttributedString, Bool)] {
        func pair(_ value: Int, _ letter: String, _ color: NSColor) -> NSAttributedString {
            let text = NSMutableAttributedString(string: "\(value)", attributes: [.font: bigFont, .foregroundColor: color])
            text.append(NSAttributedString(string: letter, attributes: [.font: letterFont, .foregroundColor: color]))
            return text
        }
        let needsColor = counts.needsYou > 0 ? NSColor(srgbRed: 0.25, green: 0.14, blue: 0.01, alpha: 1) : .secondaryLabelColor
        return [(pair(counts.needsYou, "N", needsColor), counts.needsYou > 0),
                (pair(counts.yourTurn, "T", .labelColor), false)]
    }

    static func attentionWidth(_ counts: StatusCounts) -> CGFloat {
        attention(counts).reduce(0) { $0 + $1.0.size().width.rounded(.up) + 8 }
    }

    static func make(_ graphs: [StatusGraph], work: [Double]?, counts: StatusCounts?, appearance: NSAppearance) -> NSImage {
        let height = Self.height
        let machines = width(for: graphs.count)
        let workStats = work.map(WorkScale.summary)
        let workWidth: CGFloat = work == nil ? 0
            : (machines > 0 ? spacing : 0) + labelWidth + graphWidth + 1.5 + statsWidth(workStats!)
        let countsX = machines + workWidth + ((machines + workWidth) > 0 && counts != nil ? spacing : 0)
        let total = countsX + (counts.map { attentionWidth($0) } ?? 0)
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
                if let work {
                    let start = machines > 0 ? machines + spacing : 0
                    let box = NSRect(x: start + labelWidth, y: 0, width: graphWidth, height: height)
                    drawLabel("work", beside: box)
                    NSColor(white: 0.16, alpha: 1).setFill()
                    NSBezierPath(roundedRect: box, xRadius: 2, yRadius: 2).fill()
                    fillArea(WorkScale.percent(work), in: box, color: workColor)
                    drawStats(workStats!, at: box.maxX + 1.5, height: height)
                }
                if let counts {
                    var cx = countsX
                    for (text, pill) in attention(counts) {
                        let size = text.size()
                        let w = size.width.rounded(.up) + 6
                        if pill {
                            needsYouColor.setFill()
                            NSBezierPath(roundedRect: NSRect(x: cx, y: 1, width: w, height: height - 2),
                                         xRadius: 4, yRadius: 4).fill()
                        }
                        text.draw(at: NSPoint(x: cx + 3, y: (height - size.height) / 2))
                        cx += w + 2
                    }
                }
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Max, median and now, stacked top to bottom beside the work graph.
    static func statsWidth(_ summary: WorkScale.Summary) -> CGFloat {
        [summary.max, summary.median, summary.now].map {
            NSAttributedString(string: "\($0)", attributes: [.font: scaleFont]).size().width
        }.max()!.rounded(.up)
    }

    private static func drawStats(_ summary: WorkScale.Summary, at x: CGFloat, height: CGFloat) {
        let rows = [(summary.max, NSColor.secondaryLabelColor), (summary.median, NSColor.secondaryLabelColor),
                    (summary.now, NSColor.labelColor)]
        let rowHeight = height / 3
        for (index, (value, color)) in rows.enumerated() {
            let text = NSAttributedString(string: "\(value)", attributes: [.font: scaleFont, .foregroundColor: color])
            let size = text.size()
            text.draw(at: NSPoint(x: x, y: height - (CGFloat(index) + 0.5) * rowHeight - size.height / 2))
        }
    }

    /// One faint line per session (or per few sessions on a busy hour), so the height reads as a count.
    private static func drawGrid(top: Int, in box: NSRect) {
        let step = top <= 6 ? 1 : Int((Double(top) / 5).rounded(.up))
        NSColor(white: 1, alpha: 0.13).setStroke()
        var level = step
        while level < top {
            let y = (box.minY + 1 + CGFloat(level) / CGFloat(top) * (box.height - 2)).rounded() + 0.25
            let line = NSBezierPath()
            line.lineWidth = 0.5
            line.move(to: NSPoint(x: box.minX + 1, y: y))
            line.line(to: NSPoint(x: box.maxX - 1, y: y))
            line.stroke()
            level += step
        }
    }

    private static func fillArea(_ values: [Double], in box: NSRect, color: NSColor) {
        let points = Sparkline.points(values, width: box.width, height: box.height, capacity: workCapacity)
        guard points.count > 1 else { return }
        let path = NSBezierPath()
        path.move(to: NSPoint(x: box.minX + points[0].x, y: box.minY + 1))
        for point in points {
            path.line(to: NSPoint(x: box.minX + point.x, y: box.minY + point.y))
        }
        path.line(to: NSPoint(x: box.minX + points[points.count - 1].x, y: box.minY + 1))
        path.close()
        color.withAlphaComponent(0.85).setFill()
        path.fill()
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
