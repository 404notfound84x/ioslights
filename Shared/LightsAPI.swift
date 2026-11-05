import Foundation

// Talks to LED Studio's web API. Shared by the app, Siri actions, widgets and Control Center buttons.
// It tries several addresses in order (lights.local, the server, the PC...) and sticks with the first
// one that answers until it stops answering.

/// A JSON number or string (control values are one or the other).
enum JSONValue: Codable, Equatable {
    case number(Double)
    case string(String)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let d = try? c.decode(Double.self) { self = .number(d) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else { self = .null }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .number(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .bool(let b): try c.encode(b)
        case .null: try c.encodeNil()
        }
    }

    var double: Double? {
        if case .number(let d) = self { return d }
        return nil
    }

    var string: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    var any: Any {
        switch self {
        case .number(let d): return d
        case .string(let s): return s
        case .bool(let b): return b
        case .null: return NSNull()
        }
    }
}

/// One adjustable control (slider or color) of an effect.
struct EffectControl: Decodable, Identifiable, Equatable {
    let key: String
    let label: String
    let type: String
    let min: Double?
    let max: Double?
    let step: Double?
    let defaultValue: JSONValue?

    var id: String { key }
    var isColor: Bool { type == "color" }

    enum CodingKeys: String, CodingKey {
        case key, label, type, min, max, step
        case defaultValue = "default"
    }
}

struct PresetInfo: Decodable {
    let label: String
    let params: [EffectControl]
}

struct LightsState: Decodable {
    struct ModeData: Decodable {
        let name: String?
        let params: [String: JSONValue]?
        let values: [String: JSONValue]?
        let type: String?
        let color: String?
        let color1: String?
        let color2: String?
        let moving: Bool?
        let speed: Double?
        let prompt: String?
    }

    struct Mode: Decodable {
        let kind: String?
        let label: String?
        let data: ModeData?
    }

    let power: Bool
    let brightness: Int
    let mode: Mode?
    let saved: [String]
    let status: String?
    let controls: [EffectControl]?
    let canUndo: Bool?
    let fadeMs: Double?
    let smoothMs: Double?
    let fps: Int?
    let idleColor: String?
    let idleBri: Double?
    let idleTimeout: Double?
    let fpsActual: Double?
    let controllerFps: Double?
    let pixels: Int?
    let version: String?
    let presets: [String: PresetInfo]?
    let effectError: String?

    enum CodingKeys: String, CodingKey {
        case power, brightness, mode, saved, status, controls, fps, pixels, version, presets
        case canUndo = "can_undo"
        case fadeMs = "fade_ms"
        case smoothMs = "smooth_ms"
        case idleColor = "idle_color"
        case idleBri = "idle_bri"
        case idleTimeout = "idle_timeout"
        case fpsActual = "fps_actual"
        case controllerFps = "controller_fps"
        case effectError = "effect_error"
    }
}

enum LightsError: LocalizedError {
    case server(String)

    var errorDescription: String? {
        switch self {
        case .server(let message): return message
        }
    }
}

/// Remembers which address worked (per process: the app, and the widgets, each keep their own).
private final class AddressCache {
    private let lock = NSLock()
    private var base: String?
    private var foundAt = Date.distantPast

    func get() -> String? {
        lock.lock(); defer { lock.unlock() }
        // re-check every 5 minutes so a higher-priority address (e.g. lights.local) wins again when it's back
        return Date().timeIntervalSince(foundAt) < 300 ? base : nil
    }

    func peek() -> String? {
        lock.lock(); defer { lock.unlock() }
        return base
    }

    func set(_ value: String?) {
        lock.lock(); defer { lock.unlock() }
        base = value
        foundAt = value == nil ? .distantPast : Date()
    }
}

enum LightsAPI {
    static let fallbackServers = [
        "http://lights.local",
        "http://192.168.50.111", "http://192.168.50.111:8000",
        "http://192.168.50.65", "http://192.168.50.65:8000",
    ]

    /// Built into the app at build time (LIGHTS_SERVERS in project.yml or the GitHub workflow input).
    static let builtInServers: [String] = {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "LightsServers") as? String) ?? ""
        let list = parse(raw)
        return list.isEmpty ? fallbackServers : list
    }()

    /// The app's Settings can replace the list (the app and Siri use it; widgets use the built-in list).
    static var servers: [String] {
        let custom = parse(UserDefaults.standard.string(forKey: "servers") ?? "")
        return custom.isEmpty ? builtInServers : custom
    }

    /// The address currently in use, if one has been found.
    static var currentServer: String? { cache.peek() }

    private static let cache = AddressCache()

    private static let probeSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2.5
        config.timeoutIntervalForResource = 3
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    static func parse(_ text: String) -> [String] {
        text.split(whereSeparator: { ", ;\n\t".contains($0) })
            .map { normalize(String($0)) }
            .filter { !$0.isEmpty }
    }

    static func normalize(_ address: String) -> String {
        var s = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return "" }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") { s = "http://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    // MARK: finding LED Studio

    private static func isAlive(_ base: String) async -> Bool {
        guard let url = URL(string: base + "/api/state") else { return false }
        do {
            let (data, response) = try await probeSession.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
            return (try? JSONDecoder().decode(LightsState.self, from: data)) != nil
        } catch {
            return false
        }
    }

    /// Tries every address at once and picks the first one in the list that answers.
    static func probe() async -> String? {
        let list = servers
        if list.isEmpty { return nil }
        let results: [Int: Bool] = await withTaskGroup(of: (Int, Bool).self) { group in
            for (index, base) in list.enumerated() {
                group.addTask { (index, await isAlive(base)) }
            }
            var found: [Int: Bool] = [:]
            for await result in group {
                found[result.0] = result.1
                // stop as soon as the best possible answer is known
                if let best = list.indices.first(where: { found[$0] != false }), found[best] == true {
                    group.cancelAll()
                    break
                }
            }
            return found
        }
        guard let best = list.indices.first(where: { results[$0] == true }) else { return nil }
        return list[best]
    }

    static func base(forceProbe: Bool = false) async throws -> String {
        if !forceProbe, let known = cache.get() { return known }
        if let found = await probe() {
            cache.set(found)
            return found
        }
        cache.set(nil)
        throw LightsError.server("Can't find LED Studio. Tried \(servers.joined(separator: ", ")). Are you on your home Wi-Fi?")
    }

    /// Finds LED Studio again right now (used by Settings).
    static func reconnect() async -> String? {
        cache.set(nil)
        return try? await base(forceProbe: true)
    }

    private static let retryCodes: Set<URLError.Code> = [
        .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .notConnectedToInternet,
        .networkConnectionLost, .timedOut,
    ]

    /// Sends a request to the current address; if it can't connect, looks for LED Studio again and retries once.
    private static func send(_ path: String, method: String = "GET", body: [String: Any]? = nil,
                             timeout: TimeInterval = 10) async throws -> Data {
        func makeRequest(_ base: String) throws -> URLRequest {
            guard let url = URL(string: base + "/api/" + path) else {
                throw LightsError.server("Bad LED Studio address: \(base)")
            }
            var request = URLRequest(url: url, timeoutInterval: timeout)
            request.httpMethod = method
            if let body = body {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
            }
            return request
        }

        let first = try await base()
        var result: (Data, URLResponse)
        do {
            result = try await URLSession.shared.data(for: makeRequest(first))
        } catch let error as URLError where retryCodes.contains(error.code) && !(error.code == .timedOut && timeout > 20) {
            cache.set(nil)
            let second = try await base(forceProbe: true)
            result = try await URLSession.shared.data(for: makeRequest(second))
        }
        let data = result.0
        let code = (result.1 as? HTTPURLResponse)?.statusCode ?? 200
        if code >= 400 {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw LightsError.server((object?["error"] as? String) ?? "LED Studio said no (\(code))")
        }
        return data
    }

    @discardableResult
    static func post(_ path: String, _ body: [String: Any], timeout: TimeInterval = 10) async throws -> [String: Any] {
        let data = try await send(path, method: "POST", body: body, timeout: timeout)
        let object = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
        if (object["ok"] as? Bool) == false {
            throw LightsError.server((object["error"] as? String) ?? "LED Studio said no")
        }
        return object
    }

    // MARK: reading

    static func state(full: Bool = false) async throws -> LightsState {
        let data = try await send(full ? "state?full=1" : "state", timeout: 6)
        return try JSONDecoder().decode(LightsState.self, from: data)
    }

    /// About 60 colors sampled along the strip, as "#rrggbb", already at the current brightness.
    static func frame() async throws -> [String] {
        struct Frame: Decodable { let colors: [String] }
        let data = try await send("frame", timeout: 3)
        return try JSONDecoder().decode(Frame.self, from: data).colors
    }

    // MARK: simple actions

    static func setPower(_ on: Bool) async throws {
        _ = try await post("power", ["on": on])
    }

    /// Returns the new power state.
    static func togglePower() async throws -> Bool {
        let result = try await post("power", [:])
        return (result["power"] as? Bool) ?? true
    }

    static func setBrightness(_ value: Int) async throws {
        _ = try await post("brightness", ["value": max(0, min(100, value))])
    }

    static func scene(_ name: String) async throws {
        _ = try await post("scene", ["name": name])
    }

    static func solid(_ hex: String) async throws {
        _ = try await post("simple", ["type": "solid", "color": hex])
    }

    static func gradient(_ c1: String, _ c2: String, moving: Bool, speed: Double) async throws {
        _ = try await post("simple", ["type": "gradient", "color1": c1, "color2": c2, "moving": moving, "speed": speed])
    }

    // MARK: effects

    static func preset(_ name: String, params: [String: Any] = [:]) async throws {
        _ = try await post("preset", ["name": name, "params": params])
    }

    /// Live slider/color changes for the current AI or custom effect.
    static func setParams(_ values: [String: Any]) async throws {
        _ = try await post("params", ["values": values])
    }

    /// Asks LED Studio's AI for a new effect. Can take 10+ seconds.
    static func makeEffect(_ prompt: String, asLayers: Bool = false) async throws -> String {
        let result = try await post("ai", ["prompt": prompt, "target": asLayers ? "builder" : "code"], timeout: 180)
        return (result["note"] as? String) ?? "Done."
    }

    static func refine(_ feedback: String) async throws -> String {
        let result = try await post("refine", ["feedback": feedback], timeout: 180)
        return (result["note"] as? String) ?? "Updated."
    }

    static func undo() async throws {
        _ = try await post("undo", [:])
    }

    // MARK: saved

    static func playSaved(_ name: String) async throws {
        _ = try await post("load", ["name": name])
    }

    static func save(_ name: String) async throws {
        _ = try await post("save", ["name": name])
    }

    static func deleteSaved(_ name: String) async throws {
        _ = try await post("delete", ["name": name])
    }

    // MARK: settings

    static func settings(_ values: [String: Any]) async throws {
        _ = try await post("settings", values)
    }
}
