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
// Pressure comes from the custom metrics map, when the machine runs mem-pressure.sh.
let withPressure = #"{"stats":{"cpu":10,"mp":90,"cm":{"memory_pressure_level":2,"agent_sessions_working":3}}}"#
expect(LivePoint.decode(withPressure)?.pressure == 2, "pressure from cm \(String(describing: LivePoint.decode(withPressure)))")
expect(LivePoint.decode(message)?.pressure == nil, "no cm means no pressure")

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
let face = StatusImage.labelFace
expect(face.glyphs.values.allSatisfy { g in g.count == face.height && Set(g.map { $0.count }).count == 1 },
       "every \(face.width)x\(face.height) glyph has \(face.height) rows of one width")
expect(StatusImage.height >= 16, "height \(StatusImage.height)")

// Averaging: one point per 5-second window, the mean of its readings.
var bucket = ReadingBucket(window: 5)
var averaged: [LivePoint] = []
for (t, cpu) in [(0.0, 10.0), (1, 20), (2, 30), (3, 40), (4, 50), (5, 60), (6, 70)] {
    if let p = bucket.add(LivePoint(cpu: cpu, mem: 50), at: t) { averaged.append(p) }
}
expect(averaged == [LivePoint(cpu: 35, mem: 50)], "averaged \(averaged)")
// Start-up fill: the hub's minutes, oldest first, each as 12 five-second points, ahead of live ones.
let minutes = LivePoint.fromMinutes([("2026-11-01 08:52:45.6Z", 30, 80), ("2026-11-01 08:51:45.6Z", 20, 70)],
                                    pressure: ["2026-11-01 08:52": 1])
expect(minutes == [LivePoint(cpu: 20, mem: 70), LivePoint(cpu: 30, mem: 80, pressure: 1)], "minutes \(minutes)")
let liveTail = [LivePoint(cpu: 99, mem: 1)]
let seededGraph = LiveMetricsService.merged(minutes: minutes, live: liveTail)
expect(seededGraph.count == 25 && seededGraph.first == minutes[0] && seededGraph[12] == minutes[1] && seededGraph.last == liveTail[0],
       "merged \(seededGraph.count)")
expect(LiveMetricsService.merged(minutes: Array(repeating: minutes[0], count: 5), live: Array(repeating: liveTail[0], count: 10)).count
       == LiveMetricsService.capacity, "merged keeps at most capacity")
// Pressure keeps the window's worst level, so a short spike still shows.
var pressureBucket = ReadingBucket(window: 5)
var worst: LivePoint?
for (t, p) in [(0.0, 0.0), (1, 2), (2, 1), (5, 0)] {
    if let point = pressureBucket.add(LivePoint(cpu: 1, mem: 1, pressure: p), at: t) { worst = point }
}
expect(worst?.pressure == 2, "window pressure \(String(describing: worst?.pressure))")

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
expect(StatusImage.attentionWidth(StatusCounts(working: 0, needsYou: 1, yourTurn: 18, stale: 0)) <= 56,
       "attention width \(StatusImage.attentionWidth(StatusCounts(working: 0, needsYou: 1, yourTurn: 18, stale: 0)))")
// Rendered gap from the N pill's right edge to the first inked pixel of "18T": empty columns
// equal to the graphs' spacing.
let attn = StatusImage.make([], work: nil, counts: StatusCounts(working: 0, needsYou: 1, yourTurn: 18, stale: 0),
                            appearance: NSAppearance(named: .darkAqua)!)
let attnRep = NSBitmapImageRep(data: attn.tiffRepresentation!)!
let scale = CGFloat(attnRep.pixelsWide) / attn.size.width
var pillEnd = -1, tStart = -1
for x in 0..<attnRep.pixelsWide {
    var amber = false, lit = false
    for y in 0..<attnRep.pixelsHigh {
        guard let c = attnRep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), c.alphaComponent > 0.1 else { continue }
        if c.redComponent > 0.8 && c.greenComponent > 0.45 && c.blueComponent < 0.35 { amber = true }
        else if c.brightnessComponent * c.alphaComponent > 0.1 { lit = true }  // any ink, faint edges too
    }
    if amber { pillEnd = x } else if lit && pillEnd >= 0 && tStart < 0 { tStart = x }
}
let gap = CGFloat(tStart - pillEnd - 1) / scale
expect(pillEnd >= 0 && tStart > pillEnd && abs(gap - StatusImage.spacing) <= 0.5, "N-to-T gap \(gap) pt (pill ends \(pillEnd), T starts \(tStart))")

// Pixel graphs: columns map newest to the right edge; rows stay inside the box.
let cols = StatusImage.columns([10, 20, 30], count: 34)
expect(cols.last! == 30 && cols.first! == nil, "newest value at the right edge, older columns empty")
expect(StatusImage.row(0, height: 20) == 1 && StatusImage.row(100, height: 20) == 18, "rows 1...18 in a 20 pt box")
let lineProbe = StatusImage.make([StatusGraph(label: "", cpu: Array(repeating: 30, count: 60), mem: Array(repeating: 70, count: 60))],
                                 work: nil, counts: nil, appearance: NSAppearance(named: .darkAqua)!)
let lineRep = NSBitmapImageRep(data: lineProbe.tiffRepresentation!)!
var lineShades = Set<String>()
for y in 0..<lineRep.pixelsHigh { for x in (lineRep.pixelsWide / 2)..<(lineRep.pixelsWide - 1) {
    if let c = lineRep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) {
        lineShades.insert("\(Int(c.redComponent * 20)),\(Int(c.greenComponent * 20)),\(Int(c.blueComponent * 20))")
    }
} }
expect(lineShades.count <= 3, "graph area has \(lineShades.count) colours; must be unsmoothed (box, CPU, RAM area only)")
// Readable on the pixel grid: the RAM area stands clear of the box, and the CPU line clear of RAM.
func brightness(_ c: NSColor) -> CGFloat { c.usingColorSpace(.deviceRGB)!.brightnessComponent }
expect(brightness(StatusImage.memAreaColor) - brightness(StatusImage.boxColor) >= 0.2,
       "RAM area too close to the box background (\(brightness(StatusImage.memAreaColor)) vs \(brightness(StatusImage.boxColor)))")
expect(brightness(StatusImage.cpuColor) - brightness(StatusImage.memAreaColor) >= 0.4,
       "CPU line too close to the RAM area (\(brightness(StatusImage.cpuColor)) vs \(brightness(StatusImage.memAreaColor)))")
// Pressure fills are dark on purpose; their hue sets them apart from the box, so measure RGB distance.
func distance(_ a: NSColor, _ b: NSColor) -> CGFloat {
    let a = a.usingColorSpace(.sRGB)!, b = b.usingColorSpace(.sRGB)!
    return sqrt(pow(a.redComponent - b.redComponent, 2) + pow(a.greenComponent - b.greenComponent, 2)
                + pow(a.blueComponent - b.blueComponent, 2))
}
for color in StatusImage.pressureColors {
    expect(distance(color, StatusImage.boxColor) >= 0.12, "pressure colour \(color) too close to the box")
    expect(brightness(StatusImage.cpuColor) - brightness(color) >= 0.25, "CPU line too close to pressure colour \(color)")
}
// Each RAM column takes its pressure colour: green while normal, red once critical, grey with no data.
func pixel(_ image: NSImage, _ x: Int, _ yFromBottom: Int) -> NSColor {
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let s = rep.pixelsWide / Int(image.size.width)
    return rep.colorAt(x: x * s, y: rep.pixelsHigh - 1 - yFromBottom * s)!.usingColorSpace(.sRGB)!
}
// The rendered pixel goes through a colour-space round trip, so match it to the nearest palette colour.
let palette = StatusImage.pressureColors + [StatusImage.memAreaColor, StatusImage.boxColor, StatusImage.cpuColor, StatusImage.workColor]
func same(_ a: NSColor, _ b: NSColor) -> Bool {
    func d(_ x: NSColor, _ y: NSColor) -> CGFloat {
        let x = x.usingColorSpace(.sRGB)!, y = y.usingColorSpace(.sRGB)!
        return pow(x.redComponent - y.redComponent, 2) + pow(x.greenComponent - y.greenComponent, 2)
            + pow(x.blueComponent - y.blueComponent, 2)
    }
    return palette.min { d(a, $0) < d(a, $1) } === b
}
let rising = StatusImage.make([StatusGraph(label: "", cpu: Array(repeating: 100, count: 60), mem: Array(repeating: 80, count: 60),
                                           pressure: (0..<60).map { $0 < 30 ? 0 : 2 })],
                              work: nil, counts: nil, appearance: NSAppearance(named: .darkAqua)!)
expect(same(pixel(rising, 3, 3), StatusImage.pressureColors[0]), "old columns green, got \(pixel(rising, 3, 3))")
expect(same(pixel(rising, 30, 3), StatusImage.pressureColors[2]), "new columns red, got \(pixel(rising, 30, 3))")
let noData = StatusImage.make([StatusGraph(label: "", cpu: Array(repeating: 100, count: 60), mem: Array(repeating: 80, count: 60))],
                              work: nil, counts: nil, appearance: NSAppearance(named: .darkAqua)!)
expect(same(pixel(noData, 30, 3), StatusImage.memAreaColor), "no pressure data draws grey, got \(pixel(noData, 30, 3))")
// Bars reach the bottom edge with no dark row under them; zero draws nothing; corners stay cut.
// Work columns two minutes apart, starting on a 16-minute block boundary.
func workColumns(_ counts: [Double], from minute: Int = 29_000_000) -> [WorkScale.Column] {
    counts.enumerated().map { WorkScale.Column(minute: minute + 2 * $0.offset, count: $0.element) }
}
let busyWork = StatusImage.make([], work: workColumns(Array(repeating: 3, count: 34)), counts: nil, appearance: NSAppearance(named: .darkAqua)!)
let idleWork = StatusImage.make([], work: workColumns(Array(repeating: 0, count: 34)), counts: nil, appearance: NSAppearance(named: .darkAqua)!)
func purple(_ c: NSColor) -> Bool { c.alphaComponent > 0.9 && c.blueComponent > 0.7 && c.redComponent > 0.35 && c.greenComponent < 0.6 }
expect(purple(pixel(busyWork, 10, 0)), "work bar must reach the bottom row, got \(pixel(busyWork, 10, 0))")
expect(!purple(pixel(idleWork, 10, 0)), "zero sessions must draw no bar")
expect(pixel(busyWork, 0, 0).alphaComponent < 0.1 && pixel(busyWork, 33, 0).alphaComponent < 0.1, "bottom corners stay cut")
expect(same(pixel(rising, 3, 0), StatusImage.pressureColors[0]), "RAM area reaches the bottom row, got \(pixel(rising, 3, 0))")
// Scrolling, not redrawing: one more point moves every column left by one and changes none of them.
// Run through the real capacity, so a graph that holds more points than it has columns reds here.
let width = Int(StatusImage.graphWidth)
let series = (0..<LiveMetricsService.capacity).map { Double(($0 * 37) % 100) }
let before = StatusImage.columns(series, count: width)
let after = StatusImage.columns(Array((series + [55]).suffix(LiveMetricsService.capacity)), count: width)
expect(Array(after.prefix(width - 1)) == Array(before.suffix(width - 1)) && after.last! == 55, "live graph redraws its history")
// Work columns are two fixed minutes each: a new minute never changes a finished column.
let workMinutes = ["2026-11-01 08:50": 2.0, "2026-11-01 08:51": 4, "2026-11-01 08:52": 6]
expect(WorkScale.columns(perMinute: workMinutes).map(\.count) == [3, 6], "work columns \(WorkScale.columns(perMinute: workMinutes))")
expect(WorkScale.columns(perMinute: workMinutes).map(\.minute) == [29_892_050, 29_892_052], "column start minutes (UTC)")
var workLater = workMinutes; workLater["2026-11-01 08:53"] = 10
expect(WorkScale.columns(perMinute: workLater).map(\.count) == [3, 8], "a new minute only changes the newest column")
let workHour = Dictionary(uniqueKeysWithValues: (0..<90).map { (String(format: "2026-11-01 %02d:%02d", 7 + $0 / 60, $0 % 60), Double($0)) })
expect(WorkScale.columns(perMinute: workHour).count == width, "work graph holds one column per pixel")
// The work graph's median steps: one per 16-minute block (8 columns), cyan, fixed in clock time.
let stepWork = workColumns((0..<34).map { Double($0 < 8 ? 1 : $0 < 16 ? 2 : $0 < 24 ? 3 : 4) })  // top 5
expect(WorkScale.medianSteps(stepWork).map { Int($0) } == (0..<34).map { [20, 40, 60, 80, 80][$0 / 8] }, "median steps")
let stepImage = StatusImage.make([], work: stepWork, counts: nil, appearance: NSAppearance(named: .darkAqua)!)
for (col, pct) in [(3, 20.0), (12, 40.0), (20, 60.0), (25, 80.0)] {  // 28+ sits under the corner number
    let r = StatusImage.row(pct, height: Int(StatusImage.height))
    expect(same(pixel(stepImage, col, r), StatusImage.cpuColor), "median step missing at column \(col), row \(r)")
}
// A new column scrolls the steps one pixel and changes no finished block's step.
let stepLater = Array((stepWork + [WorkScale.Column(minute: stepWork.last!.minute + 2, count: 4)]).suffix(34))
expect(Array(WorkScale.medianSteps(stepLater).prefix(33)) == Array(WorkScale.medianSteps(stepWork).suffix(33)),
       "finished median steps changed when a new column arrived")
// Out-of-range pressure never traps: huge values clamp to critical, NaN and negatives draw grey.
expect(StatusImage.memColor(1e300) === StatusImage.pressureColors[2] && StatusImage.memColor(.infinity) === StatusImage.memColor(.nan),
       "out-of-range pressure")
expect(StatusImage.memColor(.nan) === StatusImage.memAreaColor && StatusImage.memColor(-1) === StatusImage.memAreaColor, "NaN and negative are grey")

// Proportional: a wide W takes more room than a narrow I.
expect(PixelFace.medium.length("W") == 5 && PixelFace.medium.length("I") == 3, "proportional widths")
expect(PixelFace.medium.length("BOX") == 4 + 1 + 4 + 1 + 4, "BOX width \(PixelFace.medium.length("BOX"))")

if failures == 0 { print("ok") }
exit(failures == 0 ? 0 : 1)
