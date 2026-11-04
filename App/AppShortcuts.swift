import AppIntents

/// Phrases Siri understands with no setup. "Lights" is the app's name; "Room Lights" also works.
struct LightsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LightsOnIntent(),
            phrases: ["Turn on \(.applicationName)", "\(.applicationName) on", "Turn the \(.applicationName) on"],
            shortTitle: "Lights On",
            systemImageName: "lightbulb.fill"
        )
        AppShortcut(
            intent: LightsOffIntent(),
            phrases: ["Turn off \(.applicationName)", "\(.applicationName) off", "Turn the \(.applicationName) off"],
            shortTitle: "Lights Off",
            systemImageName: "lightbulb.slash"
        )
        AppShortcut(
            intent: SetBrightnessIntent(),
            phrases: ["Set \(.applicationName) brightness", "Change \(.applicationName) brightness", "Dim the \(.applicationName)"],
            shortTitle: "Brightness",
            systemImageName: "sun.max"
        )
        AppShortcut(
            intent: SceneIntent(),
            phrases: ["\(.applicationName) \(\.$scene) mode", "Set \(.applicationName) to \(\.$scene)", "\(\.$scene) scene on \(.applicationName)"],
            shortTitle: "Scene",
            systemImageName: "theatermasks"
        )
        AppShortcut(
            intent: ColorIntent(),
            phrases: ["Turn \(.applicationName) \(\.$color)", "Make \(.applicationName) \(\.$color)"],
            shortTitle: "Color",
            systemImageName: "paintpalette"
        )
        AppShortcut(
            intent: PlaySavedIntent(),
            phrases: ["Play \(\.$effect) on \(.applicationName)", "\(.applicationName) play \(\.$effect)"],
            shortTitle: "Play Saved",
            systemImageName: "play.circle"
        )
        AppShortcut(
            intent: MakeEffectIntent(),
            phrases: ["Make an effect on \(.applicationName)", "New \(.applicationName) effect", "Create a \(.applicationName) effect"],
            shortTitle: "Make Effect",
            systemImageName: "sparkles"
        )
    }
}
