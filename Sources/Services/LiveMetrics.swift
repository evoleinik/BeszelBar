import Foundation

/// One live reading for a system: CPU and memory use, in percent, and memory pressure
/// (0 normal, 1 warning, 2 critical) when the machine runs mem-pressure.sh.
struct LivePoint: Equatable {
    let cpu: Double
    let mem: Double
    var pressure: Double? = nil

    static let pressureKey = "memory_pressure_level"

    private struct Message: Decodable {
        struct Stats: Decodable {
            let cpu: Double?
            let mp: Double?
            let cm: [String: Double]?  // custom metrics, henrygd/beszel#2562
        }
        let stats: Stats?
    }

    /// Decodes a Beszel `rt_metrics` message (the agent's combined data).
    static func decode(_ json: String) -> LivePoint? {
        guard let message = try? JSONDecoder().decode(Message.self, from: Data(json.utf8)),
              let cpu = message.stats?.cpu, let mem = message.stats?.mp else { return nil }
        return LivePoint(cpu: cpu, mem: mem, pressure: message.stats?.cm?[pressureKey])
    }

    /// The hub's one-minute rows as points, oldest first. Pressure joins by minute, the first 16
    /// characters of `created` ("2026-11-01 08:52"), since it lives in a separate collection.
    static func fromMinutes(_ rows: [(created: String, cpu: Double, mem: Double)],
                            pressure: [String: Double]) -> [LivePoint] {
        rows.sorted { $0.created < $1.created }.map {
            LivePoint(cpu: $0.cpu, mem: $0.mem, pressure: pressure[String($0.created.prefix(16))])
        }
    }
}

/// Averages one-second readings into one point per window, so the graph moves calmly.
/// Pressure keeps the window's highest level, so a short spike still shows.
struct ReadingBucket {
    let window: Double
    private var start: Double?
    private var cpu = 0.0
    private var mem = 0.0
    private var count = 0
    private var pressure: Double?  // the window's worst

    init(window: Double) { self.window = window }

    /// Adds a reading taken at `time` (seconds). Returns the window's average once the window has passed.
    mutating func add(_ point: LivePoint, at time: Double) -> LivePoint? {
        if start == nil { start = time }
        cpu += point.cpu
        mem += point.mem
        if let p = point.pressure { pressure = max(pressure ?? p, p) }
        count += 1
        guard let begun = start, time - begun >= window else { return nil }
        let average = LivePoint(cpu: cpu / Double(count), mem: mem / Double(count), pressure: pressure)
        start = nil
        pressure = nil
        cpu = 0
        mem = 0
        count = 0
        return average
    }
}

/// Splits a text/event-stream into events. Feed it one line at a time, without the line break.
struct SSEParser {
    struct Event: Equatable {
        let name: String
        let data: String
    }

    private var name = ""
    private var data: [String] = []

    mutating func feed(line: String) -> Event? {
        if line.isEmpty {
            defer { name = ""; data = [] }
            guard !data.isEmpty else { return nil }
            return Event(name: name.isEmpty ? "message" : name, data: data.joined(separator: "\n"))
        }
        if line.hasPrefix(":") { return nil }
        let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        var value = parts.count > 1 ? String(parts[1]) : ""
        if value.hasPrefix(" ") { value.removeFirst() }
        switch parts[0] {
        case "event": name = value
        case "data": data.append(value)
        default: break
        }
        return nil
    }
}

enum RealtimeTopic {
    /// The topic Beszel's web UI subscribes to for one system's one-second metrics. PocketBase reads
    /// `options` as a URL query parameter holding JSON.
    static func metrics(systemID: String) -> String {
        let options = #"{"query":{"system":"\#(systemID)"}}"#
        return "rt_metrics?options=" + (options.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? options)
    }
}

/// Keeps five minutes of CPU and memory per system from Beszel's realtime feed: one point per
/// five seconds, each the average of that window's one-second readings. While it runs, the hub
/// asks those agents for numbers every second. On start, the hub's last one-minute rows fill the
/// graph, so it is never empty; live points push them out over five minutes.
@MainActor
final class LiveMetricsService {
    static let shared = LiveMetricsService()
    nonisolated static let capacity = 60
    nonisolated static let window = 5.0

    private var buckets: [String: ReadingBucket] = [:]
    private var seeded: Set<String> = []

    private(set) var history: [String: [LivePoint]] = [:]
    var onUpdate: (() -> Void)?

    typealias TokenProvider = @Sendable (_ refresh: Bool) async throws -> String

    private var task: Task<Void, Never>?
    private var configKey = ""

    private nonisolated static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30          // silence allowed between messages
        config.timeoutIntervalForResource = 7 * 86400  // the stream itself stays open
        return URLSession(configuration: config)
    }()

    func configure(baseURL: String, systemIDs: [String], token: @escaping TokenProvider) {
        let key = baseURL + "|" + systemIDs.sorted().joined(separator: ",")
        guard key != configKey else { return }
        configKey = key
        task?.cancel()
        history = history.filter { systemIDs.contains($0.key) }
        buckets = buckets.filter { systemIDs.contains($0.key) }
        seeded = seeded.filter { systemIDs.contains($0) }
        guard !systemIDs.isEmpty else {
            task = nil
            return
        }
        task = Task.detached {
            var refresh = false
            while !Task.isCancelled {
                do {
                    try await Self.stream(baseURL: baseURL, systemIDs: systemIDs, token: token, refresh: refresh) { id, point in
                        await LiveMetricsService.shared.append(point, for: id)
                    }
                    refresh = false
                } catch let error as URLError where error.code == .userAuthenticationRequired {
                    refresh = true
                } catch {
                    refresh = false
                }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        configKey = ""
        history = [:]
        buckets = [:]
        seeded = []
        onUpdate?()
    }

    /// Systems whose graph has not been filled from the hub's one-minute rows yet.
    func unseeded(_ systemIDs: [String]) -> [String] { systemIDs.filter { !seeded.contains($0) } }

    /// Fills a system's graph from the hub's last minutes, once, ahead of any live points.
    func seed(_ minutes: [LivePoint], for systemID: String) {
        guard !seeded.contains(systemID) else { return }
        seeded.insert(systemID)
        history[systemID] = Self.merged(minutes: minutes, live: history[systemID] ?? [])
        onUpdate?()
    }

    /// Each minute becomes one point per window, older than every live point; the newest
    /// `capacity` points are kept.
    nonisolated static func merged(minutes: [LivePoint], live: [LivePoint]) -> [LivePoint] {
        let perMinute = Int(60 / window)
        let filled = minutes.flatMap { Array(repeating: $0, count: perMinute) }
        return Array((filled + live).suffix(capacity))
    }

    private func append(_ reading: LivePoint, for systemID: String) {
        var bucket = buckets[systemID] ?? ReadingBucket(window: Self.window)
        let averaged = bucket.add(reading, at: Date().timeIntervalSince1970)
        buckets[systemID] = bucket
        guard let point = averaged else { return }
        var points = history[systemID] ?? []
        points.append(point)
        if points.count > Self.capacity { points.removeFirst(points.count - Self.capacity) }
        history[systemID] = points
        onUpdate?()
    }

    private nonisolated static func stream(baseURL: String, systemIDs: [String], token: TokenProvider, refresh: Bool,
                                           deliver: @escaping @Sendable (String, LivePoint) async -> Void) async throws {
        guard let url = URL(string: baseURL + "/api/realtime") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }

        let topics = Dictionary(uniqueKeysWithValues: systemIDs.map { (RealtimeTopic.metrics(systemID: $0), $0) })
        var parser = SSEParser()
        var line: [UInt8] = []
        // AsyncBytes.lines drops blank lines, which end SSE events, so split lines by hand.
        for try await byte in bytes {
            if byte == 0x0A {
                let text = String(decoding: line, as: UTF8.self)
                line.removeAll(keepingCapacity: true)
                guard let event = parser.feed(line: text) else { continue }
                if event.name == "PB_CONNECT" {
                    try await subscribe(baseURL: baseURL, event: event, topics: Array(topics.keys),
                                        token: try await token(refresh))
                } else if let systemID = topics[event.name], let point = LivePoint.decode(event.data) {
                    await deliver(systemID, point)
                }
            } else if byte != 0x0D {
                line.append(byte)
            }
        }
    }

    private nonisolated static func subscribe(baseURL: String, event: SSEParser.Event, topics: [String],
                                              token: String) async throws {
        struct Connect: Decodable { let clientId: String }
        struct Body: Encodable {
            let clientId: String
            let subscriptions: [String]
        }
        let clientId = try JSONDecoder().decode(Connect.self, from: Data(event.data.utf8)).clientId
        guard let url = URL(string: baseURL + "/api/realtime") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(Body(clientId: clientId, subscriptions: topics))
        let (_, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 { throw URLError(.userAuthenticationRequired) }
        guard (200..<300).contains(status) else { throw URLError(.badServerResponse) }
    }
}
