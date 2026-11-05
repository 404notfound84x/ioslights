import AppIntents
import WidgetKit

// Actions for Siri, the Shortcuts app, widgets and Control Center. Each one calls LED Studio.

enum LightScene: String, AppEnum, CaseIterable {
    case day, evening, night, movie

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Scene"
    static let caseDisplayRepresentations: [LightScene: DisplayRepresentation] = [
        .day: "Day",
        .evening: "Evening",
        .night: "Night",
        .movie: "Movie",
    ]

    var title: String { rawValue.capitalized }

    /// Matches SCENES in LED Studio's server.py (used for the swatch color and brightness shown in the app).
    var hex: String {
        switch self {
        case .day: return "#ffd7a8"
        case .evening: return "#ff9a3c"
        case .night: return "#7a1408"
        case .movie: return "#3a1a6a"
        }
    }

    var brightness: Int {
        switch self {
        case .day: return 100
        case .evening: return 45
        case .night: return 12
        case .movie: return 25
        }
    }
}

enum LightColor: String, AppEnum, CaseIterable {
    case warmWhite, white, red, orange, yellow, green, teal, blue, purple, pink

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Color"
    static let caseDisplayRepresentations: [LightColor: DisplayRepresentation] = [
        .warmWhite: "Warm White",
        .white: "White",
        .red: "Red",
        .orange: "Orange",
        .yellow: "Yellow",
        .green: "Green",
        .teal: "Teal",
        .blue: "Blue",
        .purple: "Purple",
        .pink: "Pink",
    ]

    var title: String {
        switch self {
        case .warmWhite: return "warm white"
        default: return rawValue
        }
    }

    var hex: String {
        switch self {
        case .warmWhite: return "#ffb46e"
        case .white: return "#ffffff"
        case .red: return "#ff1a00"
        case .orange: return "#ff7a1a"
        case .yellow: return "#ffc800"
        case .green: return "#20ff50"
        case .teal: return "#00e0b0"
        case .blue: return "#1e3cff"
        case .purple: return "#8c00ff"
        case .pink: return "#ff2a8c"
        }
    }
}

enum LightEffect: String, AppEnum, CaseIterable {
    case rainbow, flow, breathe, fire, ocean, sunset, aurora, twinkle, comet, candle

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Effect"
    static let caseDisplayRepresentations: [LightEffect: DisplayRepresentation] = [
        .rainbow: "Rainbow",
        .flow: "Gradient Flow",
        .breathe: "Breathe",
        .fire: "Fire",
        .ocean: "Ocean",
        .sunset: "Sunset",
        .aurora: "Aurora",
        .twinkle: "Twinkle",
        .comet: "Comet",
        .candle: "Candle",
    ]

    var title: String {
        switch self {
        case .flow: return "gradient flow"
        default: return rawValue
        }
    }
}

struct SavedEffect: AppEntity {
    let id: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Saved Effect"
    static let defaultQuery = SavedEffectQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(id)")
    }
}

struct SavedEffectQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [SavedEffect] {
        identifiers.map { SavedEffect(id: $0) }
    }

    func suggestedEntities() async throws -> [SavedEffect] {
        try await LightsAPI.state().saved.map { SavedEffect(id: $0) }
    }

    func entities(matching string: String) async throws -> [SavedEffect] {
        try await suggestedEntities().filter { $0.id.localizedCaseInsensitiveContains(string) }
    }
}

private func refreshWidgets() {
    WidgetCenter.shared.reloadAllTimelines()
}

struct LightsOnIntent: AppIntent {
    static let title: LocalizedStringResource = "Turn Lights On"

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await LightsAPI.setPower(true)
        refreshWidgets()
        return .result(dialog: "Lights on.")
    }
}

struct LightsOffIntent: AppIntent {
    static let title: LocalizedStringResource = "Turn Lights Off"

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await LightsAPI.setPower(false)
        refreshWidgets()
        return .result(dialog: "Lights off.")
    }
}

struct TogglePowerIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Lights"

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let on = try await LightsAPI.togglePower()
        refreshWidgets()
        let word = on ? "on" : "off"
        return .result(dialog: "Lights \(word).")
    }
}

/// Used by the Control Center toggle (the system fills in `value`).
struct SetPowerIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Set Lights Power"

    @Parameter(title: "On")
    var value: Bool

    func perform() async throws -> some IntentResult {
        try await LightsAPI.setPower(value)
        refreshWidgets()
        return .result()
    }
}

struct SetBrightnessIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Lights Brightness"

    @Parameter(title: "Brightness", requestValueDialog: "What brightness, from 0 to 100?")
    var level: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Set the lights to \(\.$level)%")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let value = max(0, min(100, level))
        try await LightsAPI.setBrightness(value)
        refreshWidgets()
        return .result(dialog: "Brightness \(value) percent.")
    }
}

/// The widget's dimmer / brighter buttons.
struct BrightnessStepIntent: AppIntent {
    static let title: LocalizedStringResource = "Change Lights Brightness"
    static let isDiscoverable = false

    @Parameter(title: "Change")
    var delta: Int

    init() {}

    init(delta: Int) {
        self.delta = delta
    }

    func perform() async throws -> some IntentResult {
        let current = try await LightsAPI.state().brightness
        try await LightsAPI.setBrightness(current + delta)
        refreshWidgets()
        return .result()
    }
}

struct SceneIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Lights Scene"

    @Parameter(title: "Scene")
    var scene: LightScene

    init() {}

    init(scene: LightScene) {
        self.scene = scene
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await LightsAPI.scene(scene.rawValue)
        refreshWidgets()
        let name = scene.title
        return .result(dialog: "\(name) scene on.")
    }
}

struct ColorIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Lights Color"

    @Parameter(title: "Color")
    var color: LightColor

    init() {}

    init(color: LightColor) {
        self.color = color
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await LightsAPI.solid(color.hex)
        try await LightsAPI.setPower(true)
        refreshWidgets()
        let name = color.title
        return .result(dialog: "Lights set to \(name).")
    }
}

struct PresetIntent: AppIntent {
    static let title: LocalizedStringResource = "Play Lights Effect"

    @Parameter(title: "Effect")
    var effect: LightEffect

    init() {}

    init(effect: LightEffect) {
        self.effect = effect
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await LightsAPI.preset(effect.rawValue)
        try await LightsAPI.setPower(true)
        refreshWidgets()
        let name = effect.title
        return .result(dialog: "Playing \(name).")
    }
}

struct PlaySavedIntent: AppIntent {
    static let title: LocalizedStringResource = "Play Saved Effect"

    @Parameter(title: "Effect")
    var effect: SavedEffect

    init() {}

    init(name: String) {
        self.effect = SavedEffect(id: name)
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await LightsAPI.playSaved(effect.id)
        try await LightsAPI.setPower(true)
        refreshWidgets()
        let name = effect.id
        return .result(dialog: "Playing \(name).")
    }
}

struct MakeEffectIntent: AppIntent {
    static let title: LocalizedStringResource = "Make a Lights Effect"

    @Parameter(title: "Description", requestValueDialog: "What should the lights do?")
    var prompt: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        _ = try await LightsAPI.makeEffect(prompt)
        refreshWidgets()
        return .result(dialog: "Done. It's playing now.")
    }
}
