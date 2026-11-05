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
    static let panel2 = Color.white.opacity(0.05)
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

struct PresetItem: Identifiable {
    let key: String
    let label: String
    let params: [EffectControl]
    var id: String { key }
}

@MainActor
final class LightsModel: ObservableObject {
    @Published var state: LightsState?
    @Published var presets: [PresetItem] = []
    @Published var brightness: Double = 80
    @Published var colors: [Color] = []
    @Published var problem: String?
    @Published var server: String?
    @Published var aiBusy = false
    @Published var aiNote = ""
    @Published var fixBusy = false
    @Published var fixNote = ""
    /// Values of the current effect's controls (AI/custom code controls, or the preset's sliders).
    @Published var controlValues: [String: JSONValue] = [:]

    var dragging = false
    private var lastBrightnessSend = Date.distantPast
    private var lastControlEdit = Date.distantPast
    private var controlsSignature = ""
    private var registeredSaved: [String] = []
    private var pending: [String: Task<Void, Never>] = [:]

    static let presetOrder = ["rainbow", "flow", "breathe", "fire", "ocean", "sunset", "aurora", "twinkle", "comet", "candle"]

    var power: Bool { state?.power ?? false }
    var label: String { state?.mode?.label ?? "" }
    var kind: String { state?.mode?.kind ?? "" }
    var saved: [String] { state?.saved ?? [] }
    var canUndo: Bool { state?.canUndo ?? false }
    var currentPreset: String? { kind == "preset" ? state?.mode?.data?.name : nil }

    var currentControls: [EffectControl] {
        if kind == "code" { return state?.controls ?? [] }
        if let name = currentPreset { return presets.first(where: { $0.key == name })?.params ?? [] }
        return []
    }

    func value(for control: EffectControl) -> JSONValue {
        controlValues[control.key] ?? control.defaultValue ?? .null
    }

    // MARK: syncing with LED Studio

    func refresh() async {
        do {
            let needPresets = presets.isEmpty
            let s = try await LightsAPI.state(full: needPresets)
            if needPresets, let p = s.presets {
                let keys = Self.presetOrder.filter { p[$0] != nil } + p.keys.filter { !Self.presetOrder.contains($0) }.sorted()
                presets = keys.compactMap { k in p[k].map { PresetItem(key: k, label: $0.label, params: $0.params) } }
            }
            apply(s)
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
        server = LightsAPI.currentServer
    }

    private func apply(_ s: LightsState) {
        state = s
        if !dragging && Date().timeIntervalSince(lastBrightnessSend) > 1.5 {
            brightness = Double(s.brightness)
        }
        let data = s.mode?.data
        let values = (s.mode?.kind == "code" ? data?.values : data?.params) ?? [:]
        let signature = [s.mode?.kind ?? "", s.mode?.label ?? "", data?.name ?? "",
                         (s.controls ?? []).map { $0.key }.joined(separator: ",")].joined(separator: "|")
        if signature != controlsSignature || Date().timeIntervalSince(lastControlEdit) > 3 {
            controlValues = values
            controlsSignature = signature
        }
        if s.saved != registeredSaved {  // let Siri learn the names of saved effects
            registeredSaved = s.saved
            LightsShortcuts.updateAppShortcutParameters()
        }
    }

    func pollFrame() async {
        if let hexes = try? await LightsAPI.frame() {
            colors = hexes.map { Color(hex: $0) }
        }
    }

    func reconnect() async {
        server = await LightsAPI.reconnect()
        presets = []
        await refresh()
    }

    // MARK: sending

    /// Runs an action after a short pause, replacing any earlier one with the same key (for sliders).
    func debounce(_ key: String, _ milliseconds: UInt64 = 120, _ action: @escaping () async throws -> Void) {
        pending[key]?.cancel()
        pending[key] = Task {
            try? await Task.sleep(nanoseconds: milliseconds * 1_000_000)
            if Task.isCancelled { return }
            do {
                try await action()
            } catch {
                problem = error.localizedDescription
            }
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

    func sendBrightness(final: Bool) {
        guard final || Date().timeIntervalSince(lastBrightnessSend) > 0.08 else { return }
        lastBrightnessSend = Date()
        let value = Int(brightness.rounded())
        Task {
            try? await LightsAPI.setBrightness(value)
            if final { WidgetCenter.shared.reloadAllTimelines() }
        }
    }

    func togglePower() {
        let on = !power
        run { try await LightsAPI.setPower(on) }
    }

    func scene(_ s: LightScene) {
        brightness = Double(s.brightness)
        lastBrightnessSend = Date()
        run { try await LightsAPI.scene(s.rawValue) }
    }

    func solid(_ color: Color) {
        let hex = color.hexString()
        let wasOff = !power
        debounce("look", 60) {
            try await LightsAPI.solid(hex)
            if wasOff { try await LightsAPI.setPower(true) }
        }
    }

    func gradient(_ c1: Color, _ c2: Color, moving: Bool, speed: Double) {
        let a = c1.hexString(), b = c2.hexString()
        debounce("look", 80) { try await LightsAPI.gradient(a, b, moving: moving, speed: speed) }
    }

    func playPreset(_ key: String) {
        run {
            try await LightsAPI.preset(key)
            try await LightsAPI.setPower(true)
        }
    }

    func setControl(_ control: EffectControl, _ value: JSONValue) {
        controlValues[control.key] = value
        lastControlEdit = Date()
        if let name = currentPreset {
            let params = controlValues.mapValues { $0.any }
            debounce("controls", 100) { try await LightsAPI.preset(name, params: params) }
        } else {
            let one: [String: Any] = [control.key: value.any]
            debounce("control-" + control.key, 50) { try await LightsAPI.setParams(one) }
        }
    }

    func playSaved(_ name: String) {
        run {
            try await LightsAPI.playSaved(name)
            try await LightsAPI.setPower(true)
        }
    }

    func save(_ name: String) {
        run { try await LightsAPI.save(name) }
    }

    func deleteSaved(_ name: String) {
        run { try await LightsAPI.deleteSaved(name) }
    }

    // MARK: AI

    func makeEffect(_ prompt: String, asLayers: Bool) {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !aiBusy else { return }
        aiBusy = true
        aiNote = "Writing your effect… usually 5–15 seconds."
        Task {
            do {
                aiNote = try await LightsAPI.makeEffect(text, asLayers: asLayers)
                fixNote = ""
            } catch {
                aiNote = error.localizedDescription
            }
            aiBusy = false
            await refresh()
        }
    }

    func refine(_ feedback: String) {
        let text = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !fixBusy else { return }
        fixBusy = true
        fixNote = "Changing it…"
        Task {
            do {
                let result = try await LightsAPI.refine(text)
                fixNote = result + " Not right? Tap Undo."
            } catch {
                fixNote = error.localizedDescription
            }
            fixBusy = false
            await refresh()
        }
    }

    func undo() {
        run {
            try await LightsAPI.undo()
            await MainActor.run { self.fixNote = "Went back one step." }
        }
    }
}
