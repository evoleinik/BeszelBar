// Checks the live-graph pieces: the event-stream parser, the realtime topic, message decoding and
// graph geometry. Run: scripts/check-live.sh
import Foundation

var failures = 0
func expect(_ ok: Bool, _ message: String) {
    if !ok { print("FAIL: \(message)"); failures += 1 }
}

// Event stream: blank line ends an event, comments are skipped, multi-line data joins with \n.
var parser = SSEParser()
var events: [SSEParser.Event] = []
for line in ["event: PB_CONNECT", "data: {\"clientId\":\"abc\"}", "", ": ping", "", "event: t1", "data: a", "data:b", "", "data: tail"] {
    if let e = parser.feed(line: line) { events.append(e) }
}
expect(events == [SSEParser.Event(name: "PB_CONNECT", data: "{\"clientId\":\"abc\"}"),
                  SSEParser.Event(name: "t1", data: "a\nb")], "events \(events)")

// Topic: PocketBase reads `options` as a URL query parameter holding JSON.
let topic = RealtimeTopic.metrics(systemID: "x1y2")
let options = URLComponents(string: topic)?.queryItems?.first { $0.name == "options" }?.value
expect(topic.hasPrefix("rt_metrics?options="), "topic \(topic)")
expect(options == #"{"query":{"system":"x1y2"}}"#, "options \(options ?? "nil")")

// Message: the agent's combined data, as Beszel sends it.
let message = #"{"stats":{"cpu":72.55,"mp":66.51,"m":62.7},"info":{"h":"box"},"container":[]}"#
expect(LivePoint.decode(message) == LivePoint(cpu: 72.55, mem: 66.51), "decode")
expect(LivePoint.decode(#"{"info":{}}"#) == nil, "message without stats must be nil")

// Geometry: newest point at the right edge, values clamped to the box.
let pts = Sparkline.points([10, 150, -5], width: 40, height: 16, capacity: 60)
let step = 40.0 / 59.0
expect(pts.count == 3, "count")
expect(abs(pts[2].x - 40) < 0.001 && abs(pts[0].x - (40 - 2 * step)) < 0.001, "x \(pts.map(\.x))")
expect(pts[1].y == 15 && pts[2].y == 1, "clamp \(pts.map(\.y))")
expect(Sparkline.points(Array(repeating: 5, count: 90), width: 40, height: 16, capacity: 60).count == 60, "capacity")
expect(StatusImage.width(for: 2) == 2 * StatusImage.graphWidth + StatusImage.spacing,
       "width \(StatusImage.width(for: 2))")
// Names inside the graph: render one graph and check the letters never reach the box's edge
// column. The box is dark; letters are light, so a bright pixel in column 0 means they spilled out.
import AppKit
let probe = StatusImage.make([StatusGraph(label: "box", cpu: [], mem: [])], work: nil, counts: nil,
                             appearance: NSAppearance(named: .darkAqua)!)
// Antialiasing off: every label pixel is pure light or pure dark, never a blend.
let rep = NSBitmapImageRep(data: probe.tiffRepresentation!)!
var edgeBright = 0, innerBright = 0
for y in 0..<rep.pixelsHigh {
    for x in 0..<rep.pixelsWide {
        guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
        let bright = c.brightnessComponent > 0.6 && c.alphaComponent > 0.5
        if bright && x == 0 { edgeBright += 1 }
        if bright && x > 0 && x < rep.pixelsWide / 3 { innerBright += 1 }
    }
}
var shades = Set<Int>()
for y in 2..<(rep.pixelsHigh - 2) {
    for x in 1..<(rep.pixelsWide / 3) {
        guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
        shades.insert(Int((c.brightnessComponent * 20).rounded()))
    }
}
expect(shades.count <= 2, "label area has \(shades.count) shades; antialiasing must be off (only light and outline)")
expect(edgeBright == 0, "letters reach the left edge (\(edgeBright) bright pixels in column 0)")
expect(innerBright > 3, "label drawn inside the graph (\(innerBright) bright pixels)")
expect(PixelFont.length(4) <= Int(StatusImage.height) - 2, "WORK fits the height")
expect(PixelFont.glyphs.values.allSatisfy { $0.count == 5 && $0.allSatisfy { $0.count == 3 } }, "every glyph is 3x5")
let vert = PixelFont.verticalPoints("box", left: 10, midY: 10, height: 20, inset: 1)
expect(vert.map(\.0).min() == 11 && vert.map(\.0).max() == 15, "vertical label columns \(vert.map(\.0).min()!)...\(vert.map(\.0).max()!)")
expect(Set(vert.map(\.1)).count > 5, "vertical label runs up the edge")
expect(PixelFont.verticalPoints("averylongname", left: 0, midY: 10, height: 20, inset: 1).map(\.1).max()! < 20, "long names truncate to fit")
expect(StatusImage.height >= 16, "height \(StatusImage.height)")

// Averaging: one point per 5-second window, the mean of its readings.
var bucket = ReadingBucket(window: 5)
var averaged: [LivePoint] = []
for (t, cpu) in [(0.0, 10.0), (1, 20), (2, 30), (3, 40), (4, 50), (5, 60), (6, 70)] {
    if let p = bucket.add(LivePoint(cpu: cpu, mem: 50), at: t) { averaged.append(p) }
}
expect(averaged == [LivePoint(cpu: 35, mem: 50)], "averaged \(averaged)")

// Work graph: counts scale to at least 5 sessions, or the hour's peak.
expect(WorkScale.percent([1, 2, 5]) == [20, 40, 100], "work scale \(WorkScale.percent([1, 2, 5]))")
expect(WorkScale.percent([2, 10]) == [20, 100], "work scale peak")
expect(WorkScale.summary([1, 4, 2, 5, 3]) == WorkScale.Summary(max: 5, median: 3, now: 3), "summary \(WorkScale.summary([1, 4, 2, 5, 3]))")
expect(WorkScale.summary([]) == WorkScale.Summary(max: 0, median: 0, now: 0), "empty summary")
expect(WorkScale.top([1, 3]) == 5 && WorkScale.top([2, 7.2]) == 8, "scale top \(WorkScale.top([2, 7.2]))")

// Attention: N gets a pill only above zero; more digits take more room.
let calm = StatusImage.attention(StatusCounts(working: 3, needsYou: 0, yourTurn: 4, stale: 9))
let busy = StatusImage.attention(StatusCounts(working: 3, needsYou: 2, yourTurn: 18, stale: 9))
expect(calm.map(\.1) == [false, false] && busy.map(\.1) == [true, false], "pill only when something needs you")
expect(busy.map { $0.0.string } == ["2N", "18T"], "letters \(busy.map { $0.0.string })")
expect(StatusImage.attentionWidth(StatusCounts(working: 0, needsYou: 1, yourTurn: 18, stale: 0)) <= 64,
       "attention width \(StatusImage.attentionWidth(StatusCounts(working: 0, needsYou: 1, yourTurn: 18, stale: 0)))")

if failures == 0 { print("ok") }
exit(failures == 0 ? 0 : 1)
