import AppIntents
import SwiftUI
import UIKit
import WidgetKit

@main
struct LightsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}

enum Theme {
    static let accent = Color(red: 1.0, green: 0.48, blue: 0.24)
    static let accentLight = Color(red: 1.0, green: 0.77, blue: 0.54)
    static let background = Color(red: 0.055, green: 0.043, blue: 0.078)
    static let panel = Color(red: 0.09, green: 0.075, blue: 0.12)
    static let line = Color.white.opacity(0.08)
}

extension Color {
    init(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        let value = UInt64(digits, radix: 16) ?? 0
        self.init(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }

    func hexString() -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ x: CGFloat) -> Int { Int((max(0, min(1, x)) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", byte(r), byte(g), byte(b))
    }
}

@MainActor
final class LightsModel: ObservableObject {
    @Published var power = true
    @Published var brightness: Double = 80
    @Published var label = "…"
    @Published var saved: [String] = []
    @Published var colors: [Color] = []
    @Published var problem: String?
    @Published var aiBusy = false
    @Published var aiNote = ""

    var dragging = false
    private var lastBrightnessSend = Date.distantPast
    private var registeredSaved: [String] = []

    func refresh() async {
        do {
            let s = try await LightsAPI.state()
            power = s.power
            label = s.mode?.label ?? ""
            saved = s.saved
            problem = nil
            if !dragging && Date().timeIntervalSince(lastBrightnessSend) > 1.5 {
                brightness = Double(s.brightness)
            }
            if s.saved != registeredSaved {  // let Siri learn the names of saved effects
                registeredSaved = s.saved
                LightsShortcuts.updateAppShortcutParameters()
            }
        } catch {
            problem = "Can't reach LED Studio at \(LightsAPI.server). Are you on your home Wi-Fi?"
        }
    }

    func pollFrame() async {
        if let hexes = try? await LightsAPI.frame() {
            colors = hexes.map { Color(hex: $0) }
        }
    }

    func sendBrightness(final: Bool) {
        guard final || Date().timeIntervalSince(lastBrightnessSend) > 0.08 else { return }
        lastBrightnessSend = Date()
        let value = Int(brightness.rounded())
        Task {
            try? await LightsAPI.setBrightness(value)
            if final { WidgetCenter.shared.reloadAllTimelines() }
        }
    }

    func run(_ action: @escaping () async throws -> Void) {
        Task {
            do {
                try await action()
                problem = nil
            } catch {
                problem = error.localizedDescription
            }
            WidgetCenter.shared.reloadAllTimelines()
            await refresh()
        }
    }

    func togglePower() {
        power.toggle()
        let on = power
        run { try await LightsAPI.setPower(on) }
    }

    func scene(_ s: LightScene) {
        brightness = Double(s.brightness)
        lastBrightnessSend = Date()
        run { try await LightsAPI.scene(s.rawValue) }
    }

    func solid(_ color: Color) {
        let hex = color.hexString()
        run {
            try await LightsAPI.solid(hex)
            try await LightsAPI.setPower(true)
        }
    }

    func playSaved(_ name: String) {
        run {
            try await LightsAPI.playSaved(name)
            try await LightsAPI.setPower(true)
        }
    }

    func makeEffect(_ prompt: String) {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !aiBusy else { return }
        aiBusy = true
        aiNote = "Writing your effect…"
        Task {
            do {
                aiNote = try await LightsAPI.makeEffect(text)
            } catch {
                aiNote = error.localizedDescription
            }
            aiBusy = false
            await refresh()
        }
    }
}
