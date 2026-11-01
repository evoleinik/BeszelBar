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
    static let graphWidth: CGFloat = 34
    static let labelFont = NSFont.systemFont(ofSize: 6.5, weight: .bold)  // tooltips only
    static let labelInset: CGFloat = 1  // from the graph's left edge to the tops of the letters
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

    static func attentionWidth(_ counts: StatusCounts) -> CGFloat {
        attention(counts).reduce(0) { $0 + $1.0.size().width.rounded(.up) + 8 }
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
                    switch memStyle {
                    case .area:
                        pixelBars(graph.mem, in: box, color: memColor.withAlphaComponent(0.38), capacity: LiveMetricsService.capacity)
                        pixelLine(graph.cpu, in: box, color: cpuColor, capacity: LiveMetricsService.capacity)
                    case .line:
                        pixelLine(graph.mem, in: box, color: memColor, capacity: LiveMetricsService.capacity)
                        pixelLine(graph.cpu, in: box, color: cpuColor, capacity: LiveMetricsService.capacity)
                    }
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
                    drawScale("\(WorkScale.top(work))", in: box)
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

    /// The graph background: a dark box with its four corner pixels cut, drawn without smoothing.
    private static func pixelBox(_ box: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.shouldAntialias = false
        NSColor(white: 0.16, alpha: 1).setFill()
        box.fill()
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

    /// Solid one-point bars from the box bottom, one per column.
    private static func pixelBars(_ values: [Double], in box: NSRect, color: NSColor, capacity: Int) {
        let cols = columns(values, count: Int(box.width), capacity: capacity)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.shouldAntialias = false
        color.setFill()
        for (col, value) in cols.enumerated() {
            guard let value else { continue }
            let y = row(value, height: Int(box.height))
            NSRect(x: box.minX + CGFloat(col), y: box.minY + 1, width: 1, height: CGFloat(y)).fill()
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

    /// Light text with a thin dark outline, so it stays readable over the lines it covers.
    static func outlined(_ text: String, font: NSFont) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: NSColor(white: 0.95, alpha: 1),
            .strokeColor: NSColor(white: 0.16, alpha: 1),
            .strokeWidth: -5,  // negative: fill and outline together
        ])
    }

    /// How RAM is drawn: a line like CPU, or a level, a plain dim area under the CPU line, so the
    /// graph has one line and RAM stays readable where the two would cross.
    enum MemStyle { case line, area }
    static var memStyle: MemStyle = .area

    enum LabelStyle { case sidewaysPixel, uprightPixel, uprightText, uprightMono }
    static var labelStyle: LabelStyle = .uprightPixel
    static var labelFace: PixelFace = .medium

    static let labelLight = NSColor(white: 0.95, alpha: 1)
    static let labelDark = NSColor(white: 0.16, alpha: 1)

    /// The name in the 3×5 pixel font, reading bottom to top along the graph's inside left edge,
    /// over the lines. The letter tops sit `labelInset` points inside the edge.
    private static func drawLabel(_ text: String, inside box: NSRect) {
        switch labelStyle {
        case .sidewaysPixel:
            let points = PixelFont.verticalPoints(text, left: box.minX, midY: box.midY, height: box.height,
                                                  inset: Int(labelInset))
            PixelFont.draw(points, light: labelLight, outline: labelDark)
        case .uprightPixel:
            let points = labelFace.topLeftPoints(text, left: box.minX + 2, top: box.maxY - 1, maxWidth: box.width - 4)
            PixelFont.draw(points, light: labelLight, outline: labelDark)
        case .uprightText, .uprightMono:
            drawCrisp(text.uppercased(), at: NSPoint(x: box.minX + 1.5, y: box.maxY - 1.5), anchorRight: false)
        }
    }

    static var crispFont: NSFont {
        labelStyle == .uprightMono
            ? NSFont.monospacedSystemFont(ofSize: 8.5, weight: .bold)
            : NSFont.systemFont(ofSize: 9, weight: .semibold)
    }

    /// Native-resolution text on a small dark patch (no outline stroke), its top edge at `point.y`
    /// and its left (or right) edge at `point.x`, snapped to the Retina pixel grid.
    private static func drawCrisp(_ text: String, at point: NSPoint, anchorRight: Bool) {
        let string = NSAttributedString(string: text, attributes: [.font: crispFont, .foregroundColor: labelLight, .kern: 0.3])
        let size = string.size()
        let capTop = crispFont.ascender - crispFont.capHeight  // empty space above capitals
        var x = anchorRight ? point.x - size.width : point.x
        var y = point.y - size.height + capTop
        x = (x * 2).rounded() / 2
        y = (y * 2).rounded() / 2
        let patch = NSRect(x: x - 1, y: y - crispFont.descender - 1, width: size.width + 2,
                           height: crispFont.capHeight + 2)
        labelDark.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: patch, xRadius: 1.5, yRadius: 1.5).fill()
        string.draw(at: NSPoint(x: x, y: y))
    }

    /// The work graph's top value in its top-right corner, in the label style.
    private static func drawScale(_ text: String, in box: NSRect) {
        switch labelStyle {
        case .sidewaysPixel:
            PixelFont.draw(PixelFont.cornerPoints(text, right: box.maxX - 2, top: box.maxY - 1),
                           light: labelLight, outline: labelDark)
        case .uprightPixel:
            PixelFont.draw(labelFace.topRightPoints(text, right: box.maxX - 2, top: box.maxY - 1),
                           light: labelLight, outline: labelDark)
        case .uprightText, .uprightMono:
            drawCrisp(text, at: NSPoint(x: box.maxX - 1.5, y: box.maxY - 1.5), anchorRight: true)
        }
    }
}
