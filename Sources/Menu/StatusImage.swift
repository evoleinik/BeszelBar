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

/// One machine in the menu bar item: its name and its recent CPU and memory readings.
struct StatusGraph: Equatable {
    let label: String
    let cpu: [Double]
    let mem: [Double]
}

/// Draws the menu bar item: for each machine, its name turned like a book spine (reading top to
/// bottom, as on English books) and a small graph with CPU and memory lines.
enum StatusImage {
    static let height: CGFloat = 16
    static let graphWidth: CGFloat = 28
    static let labelWidth: CGFloat = 9
    static let gap: CGFloat = 2
    static let spacing: CGFloat = 5
    static let cpuColor = NSColor(srgbRed: 0.52, green: 0.72, blue: 0.92, alpha: 1)
    static let memColor = NSColor(srgbRed: 0.59, green: 0.77, blue: 0.35, alpha: 1)

    static func width(for count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * (labelWidth + gap + graphWidth) + CGFloat(count - 1) * spacing
    }

    static func make(_ graphs: [StatusGraph], appearance: NSAppearance) -> NSImage {
        let image = NSImage(size: NSSize(width: width(for: graphs.count), height: height), flipped: false) { _ in
            appearance.performAsCurrentDrawingAppearance {
                var x: CGFloat = 0
                for graph in graphs {
                    drawLabel(graph.label, in: NSRect(x: x, y: 0, width: labelWidth, height: height))
                    let box = NSRect(x: x + labelWidth + gap, y: 0, width: graphWidth, height: height)
                    NSColor(white: 0.16, alpha: 1).setFill()
                    NSBezierPath(roundedRect: box, xRadius: 2, yRadius: 2).fill()
                    stroke(graph.mem, in: box, color: memColor)
                    stroke(graph.cpu, in: box, color: cpuColor)
                    x += labelWidth + gap + graphWidth + spacing
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

    /// The name rotated a quarter turn clockwise, centred in `rect`, shrunk to fit its height.
    private static func drawLabel(_ text: String, in rect: NSRect) {
        guard !text.isEmpty else { return }
        var fontSize: CGFloat = 7.5
        var string: NSAttributedString
        repeat {
            string = NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
                .foregroundColor: NSColor.labelColor,
            ])
            fontSize -= 0.5
        } while string.size().width > rect.height && fontSize >= 4
        let size = string.size()
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: rect.midX, yBy: rect.midY)
        transform.rotate(byDegrees: -90)
        transform.concat()
        string.draw(at: NSPoint(x: -size.width / 2, y: -size.height / 2))
        NSGraphicsContext.restoreGraphicsState()
    }
}
