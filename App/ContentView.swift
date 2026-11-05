import SwiftUI

// The app mirrors the LED Studio web page: Home, Effects, Create (AI), Saved, Settings.

struct ContentView: View {
    @StateObject private var m = LightsModel()
    @AppStorage("tab") private var tab = "home"

    var body: some View {
        TabView(selection: $tab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag("home")
            EffectsView()
                .tabItem { Label("Effects", systemImage: "wand.and.stars") }
                .tag("effects")
            CreateView()
                .tabItem { Label("Create", systemImage: "sparkles") }
                .tag("create")
            SavedView()
                .tabItem { Label("Saved", systemImage: "bookmark.fill") }
                .tag("saved")
            SettingsView()
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
                .tag("settings")
        }
        .environmentObject(m)
        .task {
            while !Task.isCancelled {
                await m.refresh()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
        .task {
            while !Task.isCancelled {
                await m.pollFrame()
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }
}

// MARK: - shared pieces

/// A scrolling page with the live strip on top.
struct Page<Content: View>: View {
    @EnvironmentObject var m: LightsModel
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    StripView(colors: m.colors)
                    if let crash = m.state?.effectError, !crash.isEmpty {
                        Text(crash)
                            .font(.footnote)
                            .foregroundStyle(Color.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let problem = m.problem {
                        Text(problem)
                            .font(.footnote)
                            .foregroundStyle(Color.red.opacity(0.9))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    content
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(title)
            .refreshable { await m.refresh() }
        }
    }
}

struct StripView: View {
    let colors: [Color]

    var body: some View {
        let row = HStack(spacing: 0) {
            ForEach(Array(colors.enumerated()), id: \.offset) { item in
                Rectangle().fill(item.element)
            }
        }
        return row
            .frame(height: 24)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line, lineWidth: 1))
            .background(row.blur(radius: 14).opacity(0.6).offset(y: 8))
            .animation(.linear(duration: 0.2), value: colors)
            .accessibilityLabel("Live preview of the lights")
    }
}

struct Card<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !title.isEmpty {
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .kerning(1.2)
                    .foregroundStyle(.secondary)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1))
    }
}

struct PrimaryButton: View {
    let title: String
    var busy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy { ProgressView().tint(Color.black) }
                Text(title).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accent))
            .foregroundStyle(Color.black)
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .opacity(busy ? 0.7 : 1)
    }
}

struct SecondaryButton: View {
    let title: String
    var systemImage: String?
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage = systemImage { Image(systemName: systemImage) }
                Text(title).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel2))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }
}

/// Tappable suggestion chips that wrap onto several lines.
struct Chips: View {
    let items: [String]
    let onTap: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button {
                    onTap(item)
                } label: {
                    Text(item)
                        .font(.footnote)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// A labeled slider with its value on the right.
struct SliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var format: (Double) -> String = { String(Int($0.rounded())) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text(format(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            Slider(value: $value, in: range, step: step)
        }
    }
}

/// Sliders and color pickers for whatever is playing (preset settings or the AI's controls).
struct ControlsList: View {
    @EnvironmentObject var m: LightsModel

    var body: some View {
        VStack(spacing: 14) {
            ForEach(m.currentControls) { control in
                ControlRow(control: control)
            }
        }
    }
}

struct ControlRow: View {
    @EnvironmentObject var m: LightsModel
    let control: EffectControl

    var body: some View {
        if control.isColor {
            ColorPicker(control.label, selection: colorBinding, supportsOpacity: false)
                .font(.subheadline)
        } else {
            SliderRow(label: control.label, value: numberBinding, range: range, step: step, format: format)
        }
    }

    private var range: ClosedRange<Double> {
        let lo = control.min ?? 0
        let hi = Swift.max(control.max ?? 100, lo + 0.001)
        return lo...hi
    }

    private var step: Double {
        let s = control.step ?? 0
        return s > 0 ? s : (range.upperBound - range.lowerBound) / 100
    }

    private func format(_ v: Double) -> String {
        step >= 1 ? String(Int(v.rounded())) : String(format: "%.2f", v)
    }

    private var numberBinding: Binding<Double> {
        Binding(
            get: { Swift.min(range.upperBound, Swift.max(range.lowerBound, m.value(for: control).double ?? range.lowerBound)) },
            set: { m.setControl(control, .number($0)) }
        )
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: m.value(for: control).string ?? "#ffffff") },
            set: { m.setControl(control, .string($0.hexString())) }
        )
    }
}

// MARK: - Home

struct HomeView: View {
    @EnvironmentObject var m: LightsModel
    @State var gradientMode = false
    @State var custom = Color(hex: "#ff8a2a")
    @State var gradientStart = Color(hex: "#000000")
    @State var gradientEnd = Color(hex: "#ff5a00")
    @State var moving = false
    @State var speed: Double = 20

    let swatches = ["#ffd7a8", "#ffffff", "#ff8a2a", "#ffb000", "#ff2a00", "#ff2a6d",
                    "#ff3cc8", "#8c00ff", "#3a3aff", "#00b4ff", "#00e0b0", "#29ff6a"]

    var body: some View {
        Page(title: "Lights") {
            HStack(spacing: 12) {
                BrightnessPill(value: $m.brightness) { final in
                    m.dragging = !final
                    m.sendBrightness(final: final)
                }
                VStack(spacing: 12) {
                    PowerTile()
                    NowTile()
                }
            }
            .frame(height: 290)
            scenes
            colorCard
        }
    }

    private var scenes: some View {
        Card(title: "Scenes") {
            HStack(spacing: 8) {
                ForEach(LightScene.allCases, id: \.self) { s in
                    Button {
                        m.scene(s)
                    } label: {
                        VStack(spacing: 6) {
                            Circle()
                                .fill(Color(hex: s.hex))
                                .frame(width: 30, height: 30)
                            Text(s.title)
                                .font(.footnote.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.panel2))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var colorCard: some View {
        Card(title: "Color") {
            Picker("Type", selection: $gradientMode) {
                Text("Solid").tag(false)
                Text("Gradient").tag(true)
            }
            .pickerStyle(.segmented)
            if gradientMode {
                ColorPicker("Start", selection: $gradientStart, supportsOpacity: false)
                ColorPicker("End", selection: $gradientEnd, supportsOpacity: false)
                Toggle("Moving", isOn: $moving)
                if moving {
                    SliderRow(label: "Speed", value: $speed, range: 1...100)
                }
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                    ForEach(swatches, id: \.self) { hex in
                        Button {
                            custom = Color(hex: hex)
                        } label: {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(hex: hex))
                                .aspectRatio(1, contentMode: .fit)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Color \(hex)")
                    }
                }
                ColorPicker("Custom color", selection: $custom, supportsOpacity: false)
            }
        }
        .onChange(of: custom) { _, newValue in m.solid(newValue) }
        .onChange(of: gradientMode) { _, isGradient in
            if isGradient { sendGradient() } else { m.solid(custom) }
        }
        .onChange(of: gradientStart) { _, _ in sendGradient() }
        .onChange(of: gradientEnd) { _, _ in sendGradient() }
        .onChange(of: moving) { _, _ in sendGradient() }
        .onChange(of: speed) { _, _ in sendGradient() }
    }

    private func sendGradient() {
        m.gradient(gradientStart, gradientEnd, moving: moving, speed: speed)
    }
}

struct PowerTile: View {
    @EnvironmentObject var m: LightsModel

    var body: some View {
        Button {
            m.togglePower()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "power")
                    .font(.title2.weight(.bold))
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(m.power ? Theme.accent : Color.white.opacity(0.1)))
                    .foregroundStyle(m.power ? Color.black : Color.white)
                Spacer(minLength: 0)
                Text(m.power ? "On" : "Off")
                    .font(.title3.weight(.semibold))
                Text("Power")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 24).fill(m.power ? Theme.accent.opacity(0.18) : Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(m.power ? Theme.accent.opacity(0.5) : Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact, trigger: m.power)
    }
}

struct NowTile: View {
    @EnvironmentObject var m: LightsModel
    @AppStorage("tab") var tab = "home"

    var body: some View {
        Button {
            switch m.kind {
            case "preset": tab = "effects"
            case "code", "builder": tab = "create"
            default: break
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text("PLAYING")
                    .font(.caption2.weight(.semibold))
                    .kerning(1.2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(m.label.isEmpty ? "—" : m.label)
                    .font(.title3.weight(.semibold))
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.leading)
                Text(m.kind == "simple" || m.kind.isEmpty ? "Pick a color below" : "Tap for its controls")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 24).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Big Control Center–style brightness bar: drag anywhere (relative), or tap to jump.
struct BrightnessPill: View {
    @Binding var value: Double
    var onChange: (Bool) -> Void
    @State var startValue: Double? = nil

    var body: some View {
        GeometryReader { geo in
            let height = Swift.max(geo.size.height, 1)
            ZStack(alignment: .bottom) {
                Rectangle().fill(Theme.panel)
                Rectangle()
                    .fill(LinearGradient(colors: [Theme.accent, Theme.accentLight], startPoint: .bottom, endPoint: .top))
                    .frame(height: height * CGFloat(value / 100))
                VStack(spacing: 2) {
                    Text("\(Int(value.rounded()))%")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("BRIGHTNESS")
                        .font(.caption2.weight(.semibold))
                        .kerning(1.2)
                        .opacity(0.75)
                    Spacer()
                    Image(systemName: "sun.max.fill")
                        .font(.title2)
                        .foregroundStyle(value > 12 ? Color.black.opacity(0.65) : Color.white.opacity(0.6))
                }
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(Theme.line, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 28))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if startValue == nil { startValue = value }
                        let moved = Double(g.translation.height / height) * 100
                        value = Swift.min(100, Swift.max(0, (startValue ?? value) - moved))
                        onChange(false)
                    }
                    .onEnded { g in
                        if abs(g.translation.height) < 4 {
                            value = Swift.min(100, Swift.max(0, Double(1 - g.location.y / height) * 100))
                        }
                        startValue = nil
                        onChange(true)
                    }
            )
        }
        .accessibilityElement()
        .accessibilityLabel("Brightness")
        .accessibilityValue("\(Int(value.rounded())) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = Swift.min(100, value + 10)
            case .decrement: value = Swift.max(0, value - 10)
            @unknown default: break
            }
            onChange(true)
        }
    }
}

// MARK: - Effects

struct EffectsView: View {
    @EnvironmentObject var m: LightsModel

    var body: some View {
        Page(title: "Effects") {
            if !m.currentControls.isEmpty {
                Card(title: m.label) {
                    ControlsList()
                }
            }
            if m.presets.isEmpty {
                Text("Loading effects…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(m.presets) { preset in
                    Button {
                        m.playPreset(preset.key)
                    } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            LinearGradient(colors: chipColors(preset.key), startPoint: .leading, endPoint: .trailing)
                                .frame(height: 38)
                            Text(preset.label)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.panel)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(m.currentPreset == preset.key ? Theme.accent : Theme.line,
                                        lineWidth: m.currentPreset == preset.key ? 2 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func chipColors(_ key: String) -> [Color] {
        let hexes: [String]
        switch key {
        case "rainbow": hexes = ["#ff0000", "#ffff00", "#00ff00", "#00ffff", "#0000ff", "#ff00ff", "#ff0000"]
        case "flow": hexes = ["#ff2a6d", "#2a5bff", "#ff2a6d"]
        case "breathe": hexes = ["#1a0030", "#8c00ff", "#1a0030"]
        case "fire": hexes = ["#780000", "#ff7a00", "#ffb000", "#780000"]
        case "ocean": hexes = ["#000a50", "#005aa0", "#28c8be", "#000a50"]
        case "sunset": hexes = ["#ff3c00", "#ff1446", "#78008c", "#ff7800"]
        case "aurora": hexes = ["#002810", "#00ff50", "#8c00ff", "#00b4a0"]
        case "twinkle": hexes = ["#140028", "#ffd9a0", "#140028", "#ffd9a0", "#140028"]
        case "comet": hexes = ["#000000", "#000000", "#00e5ff", "#000000"]
        case "candle": hexes = ["#3a1400", "#ff8a2a", "#c85a10", "#3a1400"]
        default: hexes = ["#333333", "#555555"]
        }
        return hexes.map { Color(hex: $0) }
    }
}

// MARK: - Create (AI)

struct CreateView: View {
    @EnvironmentObject var m: LightsModel
    @State var prompt = ""
    @State var feedback = ""
    @State var asLayers = false
    @FocusState var focused: Bool

    let examples = ["black and orange gradient", "slow ocean waves", "fire along the ceiling",
                    "galaxy with twinkling stars", "white meteors with trails", "lava lamp blobs",
                    "bouncing balls", "sunrise that slowly brightens"]
    let fixes = ["slower", "faster", "less flicker", "smoother", "more contrast", "warmer colors", "add sparkles"]

    var body: some View {
        Page(title: "Create") {
            Card(title: "Describe an effect") {
                TextField("slow purple and teal waves drifting across the ceiling", text: $prompt, axis: .vertical)
                    .lineLimit(2...6)
                    .focused($focused)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel2))
                Chips(items: examples) { prompt = $0 }
                Picker("Make it", selection: $asLayers) {
                    Text("With its own controls").tag(false)
                    Text("As layers").tag(true)
                }
                .pickerStyle(.segmented)
                PrimaryButton(title: m.aiBusy ? "Working…" : "Make it", busy: m.aiBusy) {
                    focused = false
                    m.makeEffect(prompt, asLayers: asLayers)
                }
                if !m.aiNote.isEmpty {
                    Text(m.aiNote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if m.kind == "code" {
                Card(title: "Controls") {
                    if m.currentControls.isEmpty {
                        Text("This effect has no controls. Ask for some below, like “give me a speed slider”.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ControlsList()
                    }
                }
            }

            if ["code", "builder", "simple"].contains(m.kind) {
                Card(title: "Not quite right? Say what to change") {
                    TextField("too fast, and make the orange more red", text: $feedback, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($focused)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel2))
                    Chips(items: fixes) { fix in
                        feedback = feedback.isEmpty ? fix : feedback + ", " + fix
                    }
                    HStack(spacing: 10) {
                        PrimaryButton(title: m.fixBusy ? "Changing…" : "Change it", busy: m.fixBusy) {
                            focused = false
                            m.refine(feedback)
                            feedback = ""
                        }
                        SecondaryButton(title: "Undo", systemImage: "arrow.uturn.backward", disabled: !m.canUndo) {
                            m.undo()
                        }
                    }
                    if !m.fixNote.isEmpty {
                        Text(m.fixNote)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if m.kind == "builder", let server = m.server, let url = URL(string: server) {
                Card(title: "Layers") {
                    Text("This effect is made of layers. Edit them one by one on the LED Studio page (Create → Layers).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Link("Open LED Studio", destination: url)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Saved

struct SavedView: View {
    @EnvironmentObject var m: LightsModel
    @State var name = ""
    @State var note = ""
    @State var deleting: String?

    var body: some View {
        Page(title: "Saved") {
            Card(title: "Save what's playing") {
                HStack(spacing: 10) {
                    TextField("Name, e.g. Cozy evening", text: $name)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel2))
                        .submitLabel(.done)
                        .onSubmit(save)
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accent))
                        .foregroundStyle(Color.black)
                        .buttonStyle(.plain)
                }
                Text(note.isEmpty ? "Saved effects also work from Siri: “Play my Cozy evening on Lights”." : note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Card(title: "Saved") {
                if m.saved.isEmpty {
                    Text("Nothing saved yet. Set up something you like, then save it above.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(m.saved, id: \.self) { item in
                    HStack(spacing: 12) {
                        Button {
                            m.playSaved(item)
                        } label: {
                            HStack {
                                Image(systemName: "play.fill").foregroundStyle(Theme.accent)
                                Text(item).fontWeight(.semibold)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button {
                            deleting = item
                        } label: {
                            Image(systemName: "trash").foregroundStyle(Color.red.opacity(0.85))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Delete \(item)")
                    }
                    .padding(.vertical, 8)
                    if item != m.saved.last { Divider() }
                }
            }
        }
        .confirmationDialog(
            "Delete \(deleting ?? "")?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let item = deleting { m.deleteSaved(item) }
                deleting = nil
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            note = "Give it a name first."
            return
        }
        m.save(trimmed)
        note = "Saved “\(trimmed)”."
        name = ""
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var m: LightsModel
    @AppStorage("servers") var serversText = ""
    @State var fade: Double = 0.8
    @State var smooth: Double = 0.4
    @State var fps: Double = 40
    @State var idleColor = Color(hex: "#ffb46e")
    @State var idleBri: Double = 40
    @State var idleWait: Double = 2
    @State var loaded = false
    @State var finding = false

    var body: some View {
        NavigationStack {
            syncedForm
                .navigationTitle("Settings")
        }
    }

    // Split into small pieces so the Swift compiler can type-check each one quickly.

    private var form: some View {
        Form {
            connectionSection
            addressSection
            lightsSection
            fallbackSection
            siriSection
            statusSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
    }

    private var syncedForm: some View {
        let base = form
            .onAppear(perform: load)
            .onChange(of: m.state?.version) { _, _ in load() }
            .onChange(of: serversText) { _, _ in reconnectSoon() }
        return base
            .onChange(of: fade) { _, v in send("fade_ms", Int(v * 1000)) }
            .onChange(of: smooth) { _, v in send("smooth_ms", Int(v * 1000)) }
            .onChange(of: fps) { _, v in send("fps", Int(v)) }
            .onChange(of: idleColor) { _, v in send("idle_color", v.hexString()) }
            .onChange(of: idleBri) { _, v in send("idle_bri", Int(v)) }
            .onChange(of: idleWait) { _, v in send("idle_timeout", v) }
    }

    private var connectionSection: some View {
        Section {
            LabeledContent("Connected to", value: m.server ?? "Not found")
            Button(finding ? "Looking…" : "Find LED Studio again", action: findAgain)
                .disabled(finding)
            if let url = serverURL {
                Link("Open LED Studio in Safari", destination: url)
            }
        } header: {
            Text("Connection")
        }
    }

    private var serverURL: URL? {
        guard let server = m.server else { return nil }
        return URL(string: server)
    }

    private var addressSection: some View {
        Section {
            TextField(LightsAPI.builtInServers.joined(separator: "\n"), text: $serversText, axis: .vertical)
                .lineLimit(3...8)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.footnote, design: .monospaced))
        } header: {
            Text("Addresses to try, in order")
        } footer: {
            Text("One per line. The first one that answers wins. Leave it empty to use the built-in list shown in grey. Widgets and Control Center always use the built-in list.")
        }
    }

    private var lightsSection: some View {
        Section {
            SliderRow(label: "Fade between effects", value: $fade, range: 0...3, step: 0.1, format: Self.secondsOrOff1)
            SliderRow(label: "Smoothing", value: $smooth, range: 0...2, step: 0.05, format: Self.secondsOrOff2)
            SliderRow(label: "Frame rate", value: $fps, range: 10...60, step: 1, format: Self.fpsText)
        } header: {
            Text("Lights")
        } footer: {
            Text("Smoothing glides sliders, colors and brightness instead of jumping.")
        }
    }

    private var fallbackSection: some View {
        Section {
            ColorPicker("Color", selection: $idleColor, supportsOpacity: false)
            SliderRow(label: "Brightness", value: $idleBri, range: 0...100, step: 1, format: Self.percentText)
            SliderRow(label: "Wait before fading", value: $idleWait, range: 0.5...15, step: 0.5, format: Self.secondsText)
        } header: {
            Text("If LED Studio disconnects")
        } footer: {
            Text("The controller fades to this and holds it until LED Studio comes back.")
        }
    }

    private var siriSection: some View {
        Section {
            Text("For everyday light commands (“make my lights red”, “dim the bedroom lights”), add the lights to the Home app with LED Studio's HomeKit bridge. This app adds effects, scenes and AI:")
            Text("“Lights fire” · “Lights movie mode” · “Play my Cozy evening on Lights” · “Make an effect on Lights” · “Set Lights brightness”")
                .foregroundStyle(.secondary)
        } header: {
            Text("Siri")
        }
        .font(.footnote)
    }

    @ViewBuilder
    private var statusSection: some View {
        if let s = m.state {
            Section {
                LabeledContent("LED Studio", value: s.version ?? "?")
                LabeledContent("Controller", value: s.status ?? "?")
                LabeledContent("Frame rate", value: Self.frameRateText(s))
                LabeledContent("Pixels", value: String(s.pixels ?? 0))
            } header: {
                Text("Status")
            }
            .font(.footnote)
        }
    }

    // MARK: helpers

    static func secondsOrOff1(_ v: Double) -> String { v == 0 ? "Off" : String(format: "%.1f s", v) }
    static func secondsOrOff2(_ v: Double) -> String { v == 0 ? "Off" : String(format: "%.2f s", v) }
    static func secondsText(_ v: Double) -> String { String(format: "%.1f s", v) }
    static func percentText(_ v: Double) -> String { String(Int(v)) + "%" }
    static func fpsText(_ v: Double) -> String { String(Int(v)) + " fps" }

    static func frameRateText(_ s: LightsState) -> String {
        let sent = String(Int(s.fpsActual ?? 0))
        let shown: String = s.controllerFps.map { String(Int($0)) } ?? "–"
        return sent + " sent · " + shown + " shown"
    }

    private func findAgain() {
        finding = true
        Task {
            await m.reconnect()
            finding = false
        }
    }

    private func reconnectSoon() {
        let model = m
        model.debounce("servers", 800) { await model.reconnect() }
    }

    private func load() {
        guard !loaded, let s = m.state else { return }
        fade = (s.fadeMs ?? 800) / 1000
        smooth = (s.smoothMs ?? 400) / 1000
        fps = Double(s.fps ?? 40)
        idleColor = Color(hex: s.idleColor ?? "#ffb46e")
        idleBri = s.idleBri ?? 40
        idleWait = s.idleTimeout ?? 2
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { loaded = true }
    }

    private func send(_ key: String, _ value: Any) {
        guard loaded else { return }
        m.debounce("setting-" + key, 300) { try await LightsAPI.settings([key: value]) }
    }
}
