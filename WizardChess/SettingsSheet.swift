import SwiftUI

/// The game-setup sheet: who you play, how strong the computer is, which side you take,
/// the background, and sound.
struct SettingsSheet: View {
    @ObservedObject var viewModel: GameViewModel
    @Binding var feedbackEnabled: Bool
    @Environment(\.dismiss) private var dismiss

    private var customColor: Binding<Color> {
        Binding(
            get: { Color(UIColor(hex: viewModel.customBackgroundHex)) },
            set: { viewModel.customBackgroundHex = UIColor($0).hexString }
        )
    }

    /// Switches to the theme and plays its attack, so you can see it without losing a game.
    private func startPreview(_ theme: BackgroundTheme) {
        viewModel.theme = theme
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { viewModel.previewAttack() }
    }

    private func previewButton(_ title: String, symbol: String, theme: BackgroundTheme) -> some View {
        Button {
            startPreview(theme)
        } label: {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Preview attacks")
                            .font(.subheadline.weight(.semibold))
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                            previewButton("Spaceship", symbol: "sparkles", theme: .space)
                            previewButton("Shark", symbol: "water.waves", theme: .ocean)
                            previewButton("Fire dragon", symbol: "flame", theme: .sunset)
                            previewButton("Ice dragon", symbol: "snowflake", theme: .snowyNight)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Picker("Opponent", selection: $viewModel.opponent) {
                        ForEach(Opponent.allCases) { opponent in
                            Text(opponent.rawValue).tag(opponent)
                        }
                    }
                    .pickerStyle(.segmented)

                    if viewModel.opponent == .computer {
                        VStack(spacing: 8) {
                            DifficultyDial(value: $viewModel.strength)
                                .frame(width: 260, height: 260)
                            Text("Drag the needle. 0 plays at random, 100 plays as hard as it can.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("You play")
                                .font(.subheadline.weight(.semibold))
                            Picker("You play", selection: $viewModel.humanColor) {
                                Text("Black").tag(PieceColor.black)
                                Text("Red").tag(PieceColor.red)
                            }
                            .pickerStyle(.segmented)
                            Text("Switching sides starts a new game.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Who moves first")
                            .font(.subheadline.weight(.semibold))
                        Picker("Who moves first", selection: $viewModel.firstMove) {
                            Text("Black first").tag(PieceColor.black)
                            Text("Red first").tag(PieceColor.red)
                        }
                        .pickerStyle(.segmented)
                        Text("Official US rules: black moves first. Changing this starts a new game.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Force jumps", isOn: $viewModel.forcedCapture)
                        Text(viewModel.forcedCapture
                             ? "Official US rules: if you can jump, you must. Changing this starts a new game."
                             : "Jumps are optional: you can jump or make an ordinary move. Changing this starts a new game.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Background")
                            .font(.subheadline.weight(.semibold))
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(BackgroundTheme.allCases) { theme in
                                    ThemeChip(theme: theme,
                                              customHex: viewModel.customBackgroundHex,
                                              isSelected: viewModel.theme == theme)
                                        .onTapGesture { viewModel.theme = theme }
                                }
                            }
                            .padding(.horizontal, 2)
                            .padding(.vertical, 4)
                        }
                        if viewModel.theme == .custom {
                            ColorPicker("Pick a color", selection: customColor, supportsOpacity: false)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Toggle("Sound & Haptics", isOn: $feedbackEnabled)
                }
                .padding()
            }
            .navigationTitle("Game Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// One tappable background preview.
struct ThemeChip: View {
    let theme: BackgroundTheme
    let customHex: String
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(uiImage: SkyRenderer.image(for: theme, customHex: customHex, size: CGSize(width: 160, height: 220)))
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3),
                                lineWidth: isSelected ? 3 : 1)
                )
            Text(theme.rawValue)
                .font(.caption)
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(width: 84)
        .contentShape(Rectangle())
    }
}

/// A compass-style dial from 0 to 100. Drag anywhere around it to point the needle.
struct DifficultyDial: View {
    @Binding var value: Double

    private let startAngle = 135.0   // degrees clockwise from 3 o'clock: the dial starts at the lower left
    private let sweep = 270.0        // and sweeps three quarters of the way round to the lower right

    private var theta: Double { startAngle + sweep * value / 100 }
    private var tint: Color { Color(hue: 0.33 * (1 - value / 100), saturation: 0.75, brightness: 0.9) }

    private var levelName: String {
        switch value {
        case ..<15: return "Beginner"
        case ..<35: return "Casual"
        case ..<55: return "Club player"
        case ..<75: return "Strong"
        case ..<90: return "Expert"
        default: return "Master"
        }
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = size / 2 - 12   // radius of the arc's centre line

            ZStack {
                // Track and filled arc
                Circle()
                    .trim(from: 0, to: sweep / 360)
                    .stroke(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(startAngle))
                    .padding(12)
                Circle()
                    .trim(from: 0, to: sweep / 360 * value / 100)
                    .stroke(tint, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(startAngle))
                    .padding(12)

                // Tick marks: a long one every 10 points, a short one between
                Path { path in
                    for i in 0...20 {
                        let angle = (startAngle + sweep * Double(i) / 20) * .pi / 180
                        let isMajor = i % 2 == 0
                        let inner = radius - (isMajor ? 32 : 25)
                        let outer = radius - 17
                        path.move(to: CGPoint(x: center.x + inner * cos(angle), y: center.y + inner * sin(angle)))
                        path.addLine(to: CGPoint(x: center.x + outer * cos(angle), y: center.y + outer * sin(angle)))
                    }
                }
                .stroke(Color.secondary.opacity(0.6), lineWidth: 2)

                // End labels
                Text("0")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .position(x: center.x + radius * cos(startAngle * .pi / 180),
                              y: center.y + radius * sin(startAngle * .pi / 180) + 22)
                Text("100")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .position(x: center.x + radius * cos((startAngle + sweep) * .pi / 180),
                              y: center.y + radius * sin((startAngle + sweep) * .pi / 180) + 22)

                // Needle and hub
                Path { path in
                    path.move(to: center)
                    path.addLine(to: CGPoint(x: center.x + (radius - 34) * cos(theta * .pi / 180),
                                             y: center.y + (radius - 34) * sin(theta * .pi / 180)))
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                Circle()
                    .fill(tint)
                    .frame(width: 22, height: 22)
                    .position(center)

                // Readout
                Text("\(Int(value.rounded()))")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .position(x: center.x, y: center.y + radius * 0.42)
                Text(levelName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .position(x: center.x, y: center.y + radius * 0.72)
            }
            .contentShape(Rectangle())
            // High priority so dragging the dial doesn't scroll the sheet underneath it.
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in update(from: drag.location, center: center) }
            )
        }
        .sensoryFeedback(.selection, trigger: Int(value / 5))
        .accessibilityElement()
        .accessibilityLabel("Computer strength")
        .accessibilityValue("\(Int(value.rounded())), \(levelName)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(100, value + 5)
            case .decrement: value = max(0, value - 5)
            @unknown default: break
            }
        }
    }

    /// Turns a touch position into a dial value by finding its angle around the centre.
    private func update(from location: CGPoint, center: CGPoint) {
        let dx = location.x - center.x
        let dy = location.y - center.y
        guard (dx * dx + dy * dy).squareRoot() > 20 else { return }  // ignore touches on the hub

        var degrees = atan2(dy, dx) * 180 / .pi
        if degrees < 0 { degrees += 360 }

        let relative = (degrees - startAngle + 360).truncatingRemainder(dividingBy: 360)
        if relative <= sweep {
            value = relative / sweep * 100
        } else {
            // In the gap at the bottom: snap to whichever end is nearer.
            value = (relative - sweep) < (360 - sweep) / 2 ? 100 : 0
        }
    }
}
