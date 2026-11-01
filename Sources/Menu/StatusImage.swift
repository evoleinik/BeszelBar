import AppKit

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

/// Draws the menu bar item: a graph per machine (CPU line over a grey RAM area, name in the corner),
/// the work graph, then the N and T counts. Graphs are as tall as Stats draws its own.
enum StatusImage {
    /// Stats' graph height: the menu bar's thickness less a point above and below.
    static var height: CGFloat { max(16, NSStatusBar.system.thickness - 2) }
    static let graphWidth: CGFloat = 34
    static let spacing: CGFloat = 3     // between one graph and the next
    static let pillPadding: CGFloat = 3 // inside the N pill, each side
    static let needsYouColor = NSColor(srgbRed: 0.94, green: 0.62, blue: 0.15, alpha: 1)
    static let yourTurnColor = NSColor(srgbRed: 0.39, green: 0.60, blue: 0.13, alpha: 1)
    static let staleColor = NSColor(srgbRed: 0.53, green: 0.53, blue: 0.50, alpha: 1)
    static let workColor = NSColor(srgbRed: 0.50, green: 0.47, blue: 0.87, alpha: 1)
    static let bigFont = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
    static let letterFont = NSFont.systemFont(ofSize: 9, weight: .semibold)
    static let workCapacity = 60  // one point per minute: the last hour
    static let cpuColor = NSColor(srgbRed: 0x6C / 255, green: 0xD4 / 255, blue: 0xFF / 255, alpha: 1)    // bright cyan line
    static let memAreaColor = NSColor(srgbRed: 0x4A / 255, green: 0x4A / 255, blue: 0x4A / 255, alpha: 1) // grey level

    static func width(for count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * graphWidth + CGFloat(count - 1) * spacing
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

    /// Where each count sits, from the counts' left edge. The pill gets padding; after it, T's
    /// first lit pixel sits `spacing` away, the same gap as between graphs.
    static func attentionLayout(_ counts: StatusCounts) -> [(text: NSAttributedString, pill: Bool, x: CGFloat, width: CGFloat, textX: CGFloat)] {
        var x: CGFloat = 0
        return attention(counts).enumerated().map { index, item in
            let (text, pill) = item
            if index > 0 { x += spacing }
            let glyphs = text.boundingRect(with: NSSize(width: 1000, height: 100), options: [.usesDeviceMetrics, .usesLineFragmentOrigin])
            let bearing = pill ? 0 : max(0, glyphs.minX.rounded(.down))
            let width = text.size().width.rounded(.up) + (pill ? 2 * pillPadding : -bearing)
            defer { x += width }
            return (text, pill, x, width, x + (pill ? pillPadding : -bearing))
        }
    }

    static func attentionWidth(_ counts: StatusCounts) -> CGFloat {
        attentionLayout(counts).last.map { $0.x + $0.width } ?? 0
    }

    static func make(_ graphs: [StatusGraph], work: [Double]?, counts: StatusCounts?, appearance: NSAppearance) -> NSImage {
        let height = Self.height
        let machines = width(for: graphs.count)
        let workWidth: CGFloat = work == nil ? 0 : (machines > 0 ? spacing : 0) + graphWidth
        let countsX = machines + workWidth + ((machines + workWidth) > 0 && counts != nil ? spacing : 0)
        let total = countsX + (counts.map { attentionWidth($0) } ?? 0)
        let image = NSImage(size: NSSize(width: total, height: height), flipped: false) { _ in
            appearance.performAsCurrentDrawingAppearance {
                var x: CGFloat = 0
                for graph in graphs {
                    let box = NSRect(x: x, y: 0, width: graphWidth, height: height)
                    pixelBox(box)
                    pixelBars(graph.mem, in: box, color: memAreaColor, capacity: LiveMetricsService.capacity)
                    pixelLine(graph.cpu, in: box, color: cpuColor, capacity: LiveMetricsService.capacity)
                    drawLabel(graph.label, inside: box)
                    x += graphWidth + spacing
                }
                if let work {
                    let start = machines > 0 ? machines + spacing : 0
                    let box = NSRect(x: start, y: 0, width: graphWidth, height: height)
                    pixelBox(box)
                    drawGrid(top: WorkScale.top(work), in: box)
                    pixelBars(WorkScale.percent(work), in: box, color: workColor, capacity: workCapacity)
                    drawLabel("W", inside: box)
                    drawScale("\(WorkScale.summary(work).median)", in: box)
                }
                if let counts {
                    for item in attentionLayout(counts) {
                        let x = countsX + item.x
                        if item.pill {
                            needsYouColor.setFill()
                            NSBezierPath(roundedRect: NSRect(x: x, y: 1, width: item.width, height: height - 2),
                                         xRadius: 4, yRadius: 4).fill()
                        }
                        let size = item.text.size()
                        item.text.draw(at: NSPoint(x: countsX + item.textX, y: (height - size.height) / 2))
                    }
                }
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: Pixel-grid drawing, antialiasing off, one point per pixel (matches the pixel font).

    /// The value for each whole-point column of a graph, newest at the right edge. Columns
    /// older than the history are nil.
    static func columns(_ values: [Double], count: Int, capacity: Int) -> [Double?] {
        guard count > 1, capacity > 1, !values.isEmpty else { return Array(repeating: nil, count: max(0, count)) }
        let shown = Array(values.suffix(capacity))
        let missing = capacity - shown.count
        return (0..<count).map { col in
            let slot = Int((Double(col) * Double(capacity - 1) / Double(count - 1)).rounded())
            let index = slot - missing
            return index >= 0 && index < shown.count ? shown[index] : nil
        }
    }

    /// Row (in whole points from the box bottom) for a percentage, kept one point inside the box.
    static func row(_ percent: Double, height: Int) -> Int {
        1 + Int((min(max(percent, 0), 100) / 100 * Double(height - 3)).rounded())
    }

    /// The graph background: a box with its four corner pixels cut, drawn without smoothing.
    /// With a nil colour it only cuts the corners.
    private static func pixelBox(_ box: NSRect, color: NSColor? = NSColor(white: 0.16, alpha: 1)) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.shouldAntialias = false
        if let color {
            color.setFill()
            box.fill()
        }
        NSColor.clear.setFill()
        for corner in [NSPoint(x: box.minX, y: box.minY), NSPoint(x: box.maxX - 1, y: box.minY),
                       NSPoint(x: box.minX, y: box.maxY - 1), NSPoint(x: box.maxX - 1, y: box.maxY - 1)] {
            NSRect(origin: corner, size: NSSize(width: 1, height: 1)).fill(using: .clear)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// A stepped line: one pixel per column, joined to the previous column by a vertical run.
    private static func pixelLine(_ values: [Double], in box: NSRect, color: NSColor, capacity: Int) {
        let cols = columns(values, count: Int(box.width), capacity: capacity)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.shouldAntialias = false
        color.setFill()
        var previous: Int?
        for (col, value) in cols.enumerated() {
            guard let value else { previous = nil; continue }
            let y = row(value, height: Int(box.height))
            let low = min(y, previous ?? y), high = max(y, previous ?? y)
            NSRect(x: box.minX + CGFloat(col), y: box.minY + CGFloat(low), width: 1, height: CGFloat(high - low + 1)).fill()
            previous = y
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Solid one-point bars from the box bottom, one per column. `floor` is the first row filled.
    private static func pixelBars(_ values: [Double], in box: NSRect, color: NSColor, capacity: Int, floor: Int = 1) {
        let cols = columns(values, count: Int(box.width), capacity: capacity)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.shouldAntialias = false
        color.setFill()
        for (col, value) in cols.enumerated() {
            guard let value else { continue }
            let top = floor == 0 ? Int((min(max(value, 0), 100) / 100 * Double(box.height)).rounded())
                                 : row(value, height: Int(box.height))
            guard top > floor - 1 else { continue }
            NSRect(x: box.minX + CGFloat(col), y: box.minY + CGFloat(floor), width: 1, height: CGFloat(top - floor + 1)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// One faint line per session (or per few sessions on a busy hour), so the height reads as a count.
    private static func drawGrid(top: Int, in box: NSRect) {
        let step = top <= 6 ? 1 : Int((Double(top) / 5).rounded(.up))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.shouldAntialias = false
        NSColor(white: 0.24, alpha: 1).setFill()
        var level = step
        while level < top {
            let y = row(Double(level) / Double(top) * 100, height: Int(box.height))
            // Dotted: every other point, so the grid reads as a scale and not as data.
            var x = box.minX + 1
            while x < box.maxX - 1 {
                NSRect(x: x, y: box.minY + CGFloat(y), width: 1, height: 1).fill()
                x += 2
            }
            level += step
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    static let labelFace: PixelFace = .medium
    static let labelLight = NSColor(white: 0.95, alpha: 1)
    static let labelDark = NSColor(white: 0.16, alpha: 1)

    /// The name upright in the 4×6 pixel face, in the graph's top-left corner, over the lines.
    private static func drawLabel(_ text: String, inside box: NSRect) {
        PixelFont.draw(labelFace.topLeftPoints(text, left: box.minX + 2, top: box.maxY - 1, maxWidth: box.width - 4),
                       light: labelLight, outline: labelDark)
    }

    /// The work graph's median in its top-right corner.
    private static func drawScale(_ text: String, in box: NSRect) {
        PixelFont.draw(labelFace.topRightPoints(text, right: box.maxX - 2, top: box.maxY - 1),
                       light: labelLight, outline: labelDark)
    }
}
