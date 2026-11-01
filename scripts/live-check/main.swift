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
expect(StatusImage.width(for: 2) == 2 * (StatusImage.labelWidth + StatusImage.graphWidth) + StatusImage.spacing,
       "width \(StatusImage.width(for: 2))")
expect(StatusImage.labelWidth <= 12, "name column \(StatusImage.labelWidth) pt")
expect(StatusImage.height >= 16, "height \(StatusImage.height)")

// Averaging: one point per 5-second window, the mean of its readings.
var bucket = ReadingBucket(window: 5)
var averaged: [LivePoint] = []
for (t, cpu) in [(0.0, 10.0), (1, 20), (2, 30), (3, 40), (4, 50), (5, 60), (6, 70)] {
    if let p = bucket.add(LivePoint(cpu: cpu, mem: 50), at: t) { averaged.append(p) }
}
expect(averaged == [LivePoint(cpu: 35, mem: 50)], "averaged \(averaged)")

if failures == 0 { print("ok") }
exit(failures == 0 ? 0 : 1)
