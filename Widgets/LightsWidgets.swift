import AppIntents
import SwiftUI
import WidgetKit

// Home screen + Lock Screen widgets and Control Center buttons. Their buttons run the actions in
// Shared/Intents.swift directly, without opening the app.

private let accent = Color(red: 1.0, green: 0.48, blue: 0.24)
private let widgetBackground = Color(red: 0.07, green: 0.055, blue: 0.1)

private func colorFromHex(_ hex: String) -> Color {
    let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
    let value = UInt64(digits, radix: 16) ?? 0
    return Color(red: Double((value >> 16) & 0xff) / 255,
                 green: Double((value >> 8) & 0xff) / 255,
                 blue: Double(value & 0xff) / 255)
}

struct LightsEntry: TimelineEntry {
    let date: Date
    let power: Bool
    let brightness: Int
    let label: String
    let reachable: Bool
}

struct LightsProvider: TimelineProvider {
    func placeholder(in context: Context) -> LightsEntry {
        LightsEntry(date: Date(), power: true, brightness: 80, label: "Solid", reachable: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (LightsEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LightsEntry>) -> Void) {
        Task {
            let entry: LightsEntry
            if let s = try? await LightsAPI.state() {
                entry = LightsEntry(date: Date(), power: s.power, brightness: s.brightness,
                                    label: s.mode?.label ?? "", reachable: true)
            } else {
                entry = LightsEntry(date: Date(), power: false, brightness: 0, label: "Not reachable", reachable: false)
            }
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
        }
    }
}

struct PowerButtonLabel: View {
    let on: Bool

    var body: some View {
        Image(systemName: "power")
            .font(.system(size: 18, weight: .bold))
            .frame(width: 40, height: 40)
            .background(Circle().fill(on ? accent : Color.white.opacity(0.12)))
            .foregroundStyle(on ? Color.black : Color.white)
    }
}

struct StepButtonLabel: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .bold))
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.1)))
    }
}

struct SmallLightsView: View {
    let entry: LightsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Button(intent: TogglePowerIntent()) {
                    PowerButtonLabel(on: entry.power)
                }
                .buttonStyle(.plain)
                Spacer()
                Text(entry.reachable ? "\(entry.brightness)%" : "–")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
            Text(entry.power ? entry.label : "Off")
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Button(intent: BrightnessStepIntent(delta: -10)) {
                    StepButtonLabel(symbol: "sun.min")
                }
                .buttonStyle(.plain)
                Button(intent: BrightnessStepIntent(delta: 10)) {
                    StepButtonLabel(symbol: "sun.max.fill")
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(Color.white)
    }
}

struct MediumLightsView: View {
    let entry: LightsEntry

    var body: some View {
        HStack(spacing: 12) {
            SmallLightsView(entry: entry)
                .frame(maxWidth: .infinity)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(LightScene.allCases, id: \.self) { scene in
                    Button(intent: SceneIntent(scene: scene)) {
                        VStack(spacing: 4) {
                            Circle()
                                .fill(colorFromHex(scene.hex))
                                .frame(width: 16, height: 16)
                            Text(scene.title)
                                .font(.caption2.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(Color.white)
        }
    }
}

struct LightsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LightsEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            Button(intent: TogglePowerIntent()) {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: entry.power ? "lightbulb.fill" : "lightbulb")
                        .font(.title2)
                }
            }
            .buttonStyle(.plain)
            .containerBackground(Color.clear, for: .widget)
        case .systemMedium:
            MediumLightsView(entry: entry)
                .containerBackground(widgetBackground, for: .widget)
        default:
            SmallLightsView(entry: entry)
                .containerBackground(widgetBackground, for: .widget)
        }
    }
}

struct LightsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LightsWidget", provider: LightsProvider()) { entry in
            LightsWidgetView(entry: entry)
        }
        .configurationDisplayName("Lights")
        .description("Power, brightness and scenes.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}

// MARK: Control Center

struct PowerValueProvider: ControlValueProvider {
    var previewValue: Bool { true }

    func currentValue() async throws -> Bool {
        try await LightsAPI.state().power
    }
}

struct PowerControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.isaac.lights.power", provider: PowerValueProvider()) { isOn in
            ControlWidgetToggle("Lights", isOn: isOn, action: SetPowerIntent()) { on in
                Label(on ? "On" : "Off", systemImage: on ? "lightbulb.fill" : "lightbulb")
            }
        }
        .displayName("Room Lights")
        .description("Turn the room lights on or off.")
    }
}

struct MovieControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.isaac.lights.movie") {
            ControlWidgetButton(action: SceneIntent(scene: .movie)) {
                Label("Movie", systemImage: "film")
            }
        }
        .displayName("Movie Mode")
        .description("Dim, moody lights for a movie.")
    }
}

@main
struct LightsWidgetsBundle: WidgetBundle {
    var body: some Widget {
        LightsWidget()
        PowerControl()
        MovieControl()
    }
}
