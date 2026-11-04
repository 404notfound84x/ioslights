import SwiftUI

struct ContentView: View {
    @StateObject private var m = LightsModel()
    @State private var showSettings = false
    @State private var prompt = ""
    @State private var custom = Color(hex: "#ff8a2a")
    @FocusState private var promptFocused: Bool

    private let swatches = ["#ffd7a8", "#ffffff", "#ff8a2a", "#ffb000", "#ff2a00", "#ff2a6d",
                            "#ff3cc8", "#8c00ff", "#3a3aff", "#00b4ff", "#00e0b0", "#29ff6a"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    strip
                    if let problem = m.problem {
                        Text(problem)
                            .font(.footnote)
                            .foregroundStyle(Color.red.opacity(0.9))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 12) {
                        BrightnessPill(value: $m.brightness) { final in
                            m.dragging = !final
                            m.sendBrightness(final: final)
                        }
                        VStack(spacing: 12) {
                            powerTile
                            nowTile
                        }
                    }
                    .frame(height: 290)
                    scenesCard
                    colorCard
                    aiCard
                    savedCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Lights")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .refreshable { await m.refresh() }
        }
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

    // MARK: pieces

    private var strip: some View {
        HStack(spacing: 0) {
            ForEach(Array(m.colors.enumerated()), id: \.offset) { item in
                Rectangle().fill(item.element)
            }
        }
        .frame(height: 26)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line, lineWidth: 1))
        .background(
            HStack(spacing: 0) {
                ForEach(Array(m.colors.enumerated()), id: \.offset) { item in
                    Rectangle().fill(item.element)
                }
            }
            .blur(radius: 14)
            .opacity(0.6)
            .offset(y: 8)
        )
        .animation(.linear(duration: 0.2), value: m.colors)
        .accessibilityLabel("Live preview of the lights")
    }

    private var powerTile: some View {
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
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(m.power ? Theme.accent.opacity(0.18) : Theme.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(m.power ? Theme.accent.opacity(0.5) : Theme.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact, trigger: m.power)
    }

    private var nowTile: some View {
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Theme.line, lineWidth: 1))
    }

    private var scenesCard: some View {
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
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var colorCard: some View {
        Card(title: "Color") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                ForEach(swatches, id: \.self) { hex in
                    Button {
                        m.solid(Color(hex: hex))
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
                .onChange(of: custom) { _, newValue in
                    m.solid(newValue)
                }
        }
    }

    private var aiCard: some View {
        Card(title: "Make an effect") {
            TextField("slow purple and teal waves", text: $prompt, axis: .vertical)
                .lineLimit(2...5)
                .focused($promptFocused)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
            Button {
                promptFocused = false
                m.makeEffect(prompt)
            } label: {
                HStack {
                    if m.aiBusy { ProgressView().tint(Color.black) }
                    Text(m.aiBusy ? "Working…" : "Make it")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accent))
                .foregroundStyle(Color.black)
            }
            .buttonStyle(.plain)
            .disabled(m.aiBusy)
            if !m.aiNote.isEmpty {
                Text(m.aiNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var savedCard: some View {
        Card(title: "Saved") {
            if m.saved.isEmpty {
                Text("Nothing saved yet. Save effects from the LED Studio page.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(m.saved, id: \.self) { name in
                Button {
                    m.playSaved(name)
                } label: {
                    HStack {
                        Text(name).fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "play.fill").foregroundStyle(Theme.accent)
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if name != m.saved.last { Divider() }
            }
        }
    }
}

struct Card<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .kerning(1.2)
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1))
    }
}

/// Big Control Center–style brightness bar: drag anywhere (relative), or tap to jump.
struct BrightnessPill: View {
    @Binding var value: Double
    var onChange: (Bool) -> Void
    @State private var startValue: Double?

    var body: some View {
        GeometryReader { geo in
            let height = max(geo.size.height, 1)
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
                        value = min(100, max(0, (startValue ?? value) - moved))
                        onChange(false)
                    }
                    .onEnded { g in
                        if abs(g.translation.height) < 4 {
                            value = min(100, max(0, Double(1 - g.location.y / height) * 100))
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
            case .increment: value = min(100, value + 10)
            case .decrement: value = max(0, value - 10)
            @unknown default: break
            }
            onChange(true)
        }
    }
}

struct SettingsView: View {
    @AppStorage("server") private var server = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(LightsAPI.defaultServer, text: $server)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("LED Studio address")
                } footer: {
                    Text("Leave blank to use \(LightsAPI.defaultServer). Widgets and Control Center always use the address the app was built with.")
                }
                Section {
                    Text("Say things like “Turn off Lights”, “Lights movie mode”, “Turn Lights blue”, “Play Cozy evening on Lights”, or “Make an effect on Lights”.")
                        .font(.footnote)
                } header: {
                    Text("Siri")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
