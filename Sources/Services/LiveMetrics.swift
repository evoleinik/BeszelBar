import Foundation

/// One live reading for a system: CPU and memory use, in percent.
struct LivePoint: Equatable {
    let cpu: Double
    let mem: Double

    private struct Message: Decodable {
        struct Stats: Decodable {
            let cpu: Double?
            let mp: Double?
        }
        let stats: Stats?
    }

    /// Decodes a Beszel `rt_metrics` message (the agent's combined data).
    static func decode(_ json: String) -> LivePoint? {
        guard let message = try? JSONDecoder().decode(Message.self, from: Data(json.utf8)),
              let cpu = message.stats?.cpu, let mem = message.stats?.mp else { return nil }
        return LivePoint(cpu: cpu, mem: mem)
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

/// Keeps a one-minute history of live CPU and memory readings per system, from Beszel's realtime feed.
/// While it runs, the hub asks those agents for numbers every second.
@MainActor
final class LiveMetricsService {
    static let shared = LiveMetricsService()
    nonisolated static let capacity = 60

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
        onUpdate?()
    }

    private func append(_ point: LivePoint, for systemID: String) {
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
