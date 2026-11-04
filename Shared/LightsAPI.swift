import Foundation

/// Talks to LED Studio's web API. Shared by the app, Siri actions, widgets and Control Center buttons.
struct LightsState: Decodable {
    struct Mode: Decodable {
        let kind: String?
        let label: String?
    }
    let power: Bool
    let brightness: Int
    let mode: Mode?
    let saved: [String]
    let status: String?
}

enum LightsError: LocalizedError {
    case server(String)

    var errorDescription: String? {
        switch self {
        case .server(let message): return message
        }
    }
}

enum LightsAPI {
    /// Set at build time (LIGHTS_SERVER in project.yml or the GitHub workflow input).
    static let defaultServer: String =
        (Bundle.main.object(forInfoDictionaryKey: "LightsServer") as? String) ?? "http://lights.local"

    /// The app's Settings can override the address (used by the app and Siri; widgets use the built-in one).
    static var server: String {
        let saved = UserDefaults.standard.string(forKey: "server")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return saved.isEmpty ? defaultServer : saved
    }

    static func url(_ path: String) throws -> URL {
        var base = server
        if !base.lowercased().hasPrefix("http") { base = "http://" + base }
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + "/api/" + path) else {
            throw LightsError.server("Bad LED Studio address: \(base)")
        }
        return url
    }

    @discardableResult
    static func post(_ path: String, _ body: [String: Any], timeout: TimeInterval = 10) async throws -> [String: Any] {
        var request = URLRequest(url: try url(path), timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let object = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
        let code = (response as? HTTPURLResponse)?.statusCode ?? 200
        if code >= 400 || (object["ok"] as? Bool) == false {
            throw LightsError.server((object["error"] as? String) ?? "LED Studio said no (\(code))")
        }
        return object
    }

    static func state() async throws -> LightsState {
        let request = URLRequest(url: try url("state"), timeoutInterval: 6)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(LightsState.self, from: data)
    }

    /// About 60 colors sampled along the strip, as "#rrggbb", already at the current brightness.
    static func frame() async throws -> [String] {
        struct Frame: Decodable { let colors: [String] }
        let request = URLRequest(url: try url("frame"), timeoutInterval: 3)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(Frame.self, from: data).colors
    }

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

    static func playSaved(_ name: String) async throws {
        _ = try await post("load", ["name": name])
    }

    static func solid(_ hex: String) async throws {
        _ = try await post("simple", ["type": "solid", "color": hex])
    }

    /// Asks LED Studio's AI for a new effect. Can take 10+ seconds.
    static func makeEffect(_ prompt: String) async throws -> String {
        let result = try await post("ai", ["prompt": prompt, "target": "code"], timeout: 150)
        return (result["note"] as? String) ?? "Done."
    }
}
