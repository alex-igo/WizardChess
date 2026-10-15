import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = GameViewModel()
    @State private var show3D = false
    @State private var showSettings = false
    @AppStorage("feedbackEnabled") private var feedbackEnabled = true

    private var opponentSummary: String {
        viewModel.vsComputer ? "Computer · \(Int(viewModel.strength.rounded()))" : "Two Players"
    }

    var body: some View {
        ZStack {
            if show3D {
                CheckersSceneView(viewModel: viewModel)
                    .ignoresSafeArea()
            } else {
                Board2DView(viewModel: viewModel)
                    .padding(.vertical, 120)
            }

            VStack(spacing: 10) {
                HStack {
                    Button {
                        showSettings = true
                    } label: {
                        Label(opponentSummary, systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Picker("View", selection: $show3D) {
                        Text("2D").tag(false)
                        Text("3D").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 130)
                    .disabled(viewModel.sharkAttacked)
                }
                .padding(.horizontal)

                Text(viewModel.message)
                    .font(.title2.weight(.semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())

                Spacer()

                HStack(spacing: 16) {
                    Button {
                        viewModel.requestHint()
                    } label: {
                        Label(viewModel.isHinting ? "Thinking…" : "Hint", systemImage: "lightbulb")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.canRequestHint)

                    Button("New Game") { viewModel.reset() }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.bottom, 24)
            }
            .padding(.top, 8)
        }
        .background {
            ZStack {
                ThemeBackgroundView(theme: viewModel.theme, customHex: viewModel.customBackgroundHex)
                if viewModel.theme == .ocean { OceanLifeView() }
                if viewModel.theme == .snowyNight { SnowfallView() }
            }
        }
        .preferredColorScheme(viewModel.prefersLightInterface ? .light : .dark)
        .sheet(isPresented: $showSettings) {
            SettingsSheet(viewModel: viewModel, feedbackEnabled: $feedbackEnabled)
                .presentationDetents([.large])
        }
        .onAppear {
            Feedback.isEnabled = feedbackEnabled
            Feedback.prepare()
        }
        .onChange(of: viewModel.sharkStage) { _, stage in
            if stage == .stalking { show3D = true }   // the shark attack plays in the 3D view
        }
        .onChange(of: feedbackEnabled) {
            Feedback.isEnabled = feedbackEnabled
        }
    }
}

#Preview {
    ContentView()
}
