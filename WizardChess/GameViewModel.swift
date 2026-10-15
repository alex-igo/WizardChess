import Foundation
import Combine
import UIKit

/// How far the Ocean shark's visit has got: it circles the board for 5 seconds, then attacks, then the game is over.
enum SharkStage {
    case none, stalking, attacking, done
}

/// Who plays against you.
enum Opponent: String, CaseIterable, Identifiable {
    case twoPlayers = "Two Players"
    case computer = "Computer"

    var id: String { rawValue }
}

/// Connects the checkers engine to the UI: holds the current game, the selected piece,
/// turns taps into selections and moves, and asks the AI for the computer's moves.
/// Also holds the settings, which are remembered between launches.
final class GameViewModel: ObservableObject {
    @Published private(set) var state = GameState.initial()
    @Published private(set) var selected: Position?

    /// The move just played, and a counter that changes on every move or reset.
    /// The 3D scene watches the counter to know when to animate.
    @Published private(set) var lastMove: Move?
    @Published private(set) var moveCount = 0

    @Published private(set) var isThinking = false

    /// The Ocean theme's shark visits about 1 game in 10 and ends it.
    @Published private(set) var sharkStage: SharkStage = .none
    var sharkAttacked: Bool { sharkStage != .none }

    /// A suggested move for the player to move, shown as a highlight until a move is played.
    @Published private(set) var hint: Move?
    @Published private(set) var isHinting = false

    // MARK: Settings (saved between launches)

    /// How strong the computer is, from 0 (random) to 100 (as strong as it gets).
    /// Changing it takes effect from the computer's next move.
    @Published var strength: Double = 50 {
        didSet { defaults.set(strength, forKey: "strength") }
    }

    @Published var opponent: Opponent = .computer {
        didSet {
            guard opponent != oldValue else { return }
            defaults.set(opponent.rawValue, forKey: "opponent")
            aiGeneration += 1      // throw away a move the previous opponent was still working out
            isThinking = false
            selected = nil
            hint = nil
            scheduleAIMoveIfNeeded()
        }
    }

    /// The colour the person holding the phone plays against the computer. Changing it starts a new game.
    @Published var humanColor: PieceColor = .red {
        didSet {
            guard humanColor != oldValue else { return }
            defaults.set(humanColor == .black ? "black" : "red", forKey: "humanColor")
            reset()
        }
    }

    /// Official US rules force you to jump whenever you can. Turn this off to make captures
    /// optional (a common house rule). Changing it starts a new game.
    @Published var forcedCapture: Bool = true {
        didSet {
            guard forcedCapture != oldValue else { return }
            defaults.set(forcedCapture, forKey: "forcedCapture")
            reset()
        }
    }

    /// Which colour makes the first move. Official US rules say black; red is offered as a house rule.
    /// Changing it starts a new game.
    @Published var firstMove: PieceColor = .black {
        didSet {
            guard firstMove != oldValue else { return }
            defaults.set(firstMove == .black ? "black" : "red", forKey: "firstMove")
            reset()
        }
    }

    @Published var theme: BackgroundTheme = .starryNight {
        didSet { defaults.set(theme.rawValue, forKey: "theme") }
    }

    @Published var customBackgroundHex: String = "#1B2A41" {
        didSet { defaults.set(customBackgroundHex, forKey: "customBackgroundHex") }
    }

    private let defaults = UserDefaults.standard
    private var aiGeneration = 0
    /// Half-moves since the last capture or non-king move. Used to call a draw.
    private var quietPlies = 0
    private let drawAfterQuietPlies = 80
    /// Moves played so far, and the move after which this game's shark shows up (nil: no shark this game).

    init() {
        if defaults.object(forKey: "strength") != nil { strength = defaults.double(forKey: "strength") }
        if let raw = defaults.string(forKey: "opponent"), let saved = Opponent(rawValue: raw) { opponent = saved }
        if let raw = defaults.string(forKey: "theme"), let saved = BackgroundTheme(rawValue: raw) { theme = saved }
        if let hex = defaults.string(forKey: "customBackgroundHex") { customBackgroundHex = hex }
        if defaults.object(forKey: "forcedCapture") != nil { forcedCapture = defaults.bool(forKey: "forcedCapture") }
        if let raw = defaults.string(forKey: "humanColor") { humanColor = raw == "black" ? .black : .red }
        if let raw = defaults.string(forKey: "firstMove") { firstMove = raw == "red" ? .red : .black }
        state = GameState.initial(forcedCapture: forcedCapture, firstMove: firstMove)
        scheduleAIMoveIfNeeded()  // if the computer plays black, it opens
    }

    // MARK: Derived state

    var legalMoves: [Move] { state.legalMoves() }

    var movesForSelected: [Move] {
        guard let selected else { return [] }
        return legalMoves.filter { $0.from == selected }
    }

    var canRequestHint: Bool { !isGameOver && !isComputerTurn && !isHinting }

    var vsComputer: Bool { opponent == .computer }
    var isDraw: Bool { quietPlies >= drawAfterQuietPlies }
    var isGameOver: Bool { state.winner != nil || isDraw || sharkAttacked }
    var computerColor: PieceColor { humanColor.opponent }
    var isComputerTurn: Bool { vsComputer && state.turn == computerColor }

    /// When you play black against the computer, the board is turned so your pieces are nearest you.
    var boardFlipped: Bool { vsComputer && humanColor == .black }

    /// True for a pale custom background, so the menus can switch to dark text.
    var prefersLightInterface: Bool {
        theme == .custom && UIColor(hex: customBackgroundHex).perceivedBrightness > 0.65
    }

    var message: String {
        switch sharkStage {
        case .stalking:
            switch theme {
            case .space: return "Unidentified craft approaching…"
            case .sunset: return "A dragon circles overhead…"
            case .snowyNight: return "An ice dragon circles overhead…"
            default: return "Something is circling…"
            }
        case .attacking:
            switch theme {
            case .space: return "Incoming fire!"
            case .sunset: return "Dragonfire!"
            case .snowyNight: return "Frostbreath!"
            default: return "Uh oh…"
            }
        case .done: return "You Lose!"
        case .none: break
        }
        if let winner = state.winner {
            if vsComputer { return winner == humanColor ? "You win!" : "Computer wins" }
            return winner == .red ? "Red wins!" : "Black wins!"
        }
        if isDraw { return "Draw" }
        if vsComputer { return state.turn == humanColor ? "Your move" : "Computer is thinking…" }
        return state.turn == .red ? "Red to move" : "Black to move"
    }

    // MARK: Input

    /// Called when the player taps a square (or a piece standing on it).
    func tap(_ position: Position) {
        guard !isGameOver, !isComputerTurn else { return }

        // Tapping a highlighted destination plays the move.
        if let move = movesForSelected.first(where: { $0.to == position }) {
            play(move)
            return
        }

        // Tapping one of your own movable pieces selects it. Anything else clears the selection.
        let canMove = legalMoves.contains { $0.from == position }
        selected = canMove ? position : nil
    }

    /// Works out the best move for the player to move, using the strongest the search can do,
    /// and highlights it. Runs in the background so the board stays responsive.
    func requestHint() {
        guard canRequestHint else { return }
        isHinting = true
        let snapshot = state
        let movesPlayed = moveCount

        Task { @MainActor [weak self] in
            let move = await Task.detached(priority: .userInitiated) {
                CheckersAI(strength: 100).chooseMove(for: snapshot)
            }.value
            guard let self else { return }
            self.isHinting = false
            guard self.moveCount == movesPlayed else { return }  // the game moved on while we were thinking
            self.hint = move
        }
    }

    func reset() {
        aiGeneration += 1
        isThinking = false
        quietPlies = 0
        hint = nil
        sharkStage = .none
        Feedback.stopSong()
        state = GameState.initial(forcedCapture: forcedCapture, firstMove: firstMove)
        selected = nil
        lastMove = nil
        moveCount += 1
        scheduleAIMoveIfNeeded()  // the computer opens if it plays black
    }

    // MARK: Playing moves

    private func play(_ move: Move) {
        let movedKing = state[move.from]?.isKing ?? false
        guard let next = state.applying(move) else { return }

        if move.isCapture || !movedKing {
            quietPlies = 0
        } else {
            quietPlies += 1
        }

        state = next
        selected = nil
        hint = nil
        lastMove = move
        moveCount += 1

        scheduleAIMoveIfNeeded()
        checkForShark()
    }

    // MARK: The Ocean shark

    /// The 3D scene calls this when the shark has finished eating the board.
    func sharkFinishedEating() {
        if sharkStage != .none { sharkStage = .done }
    }

    /// When you lose to the computer on the Ocean background, a shark eats the board.
    private func checkForShark() {
        guard vsComputer, state.winner == computerColor else { return }
        startAttack(delay: 2.2)
    }

    /// Lets you watch the attack without having to lose: used by the "Preview attack" button in Settings.
    func previewAttack() {
        startAttack(delay: 0.6)
    }

    private func startAttack(delay: Double) {
        guard theme.hasAttack, sharkStage == .none else { return }
        let generation = aiGeneration

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))  // let the winning move finish animating
            guard let self, self.aiGeneration == generation, self.sharkStage == .none, self.theme.hasAttack else { return }
            self.aiGeneration += 1      // throw away any computer move still being worked out
            let sharkGeneration = self.aiGeneration
            self.isThinking = false
            self.selected = nil
            self.hint = nil
            self.sharkStage = .stalking
            Feedback.sharkTheme()

            try? await Task.sleep(nanoseconds: UInt64(SharkRig.stalkDuration * 1_000_000_000))
            guard self.aiGeneration == sharkGeneration, self.sharkStage == .stalking else { return }
            self.sharkStage = .attacking

            // Safety net: the 3D scene normally reports back when the board has been eaten.
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard self.aiGeneration == sharkGeneration, self.sharkStage == .attacking else { return }
            self.sharkStage = .done
        }
    }

    /// If the computer is playing and it's its turn, work out a move in the background
    /// and play it after a short pause (long enough for the previous animation to play).
    private func scheduleAIMoveIfNeeded() {
        guard vsComputer,
              state.turn == computerColor,
              !isGameOver,
              !isThinking else { return }

        isThinking = true
        let snapshot = state
        let level = Int(strength.rounded())
        let generation = aiGeneration
        let started = Date()
        let hops = max((lastMove?.path.count ?? 1) - 1, 1)
        let minimumDelay = 0.7 + (hops > 1 ? 1.05 : 0.4) * Double(hops)  // multi-jumps animate slower

        Task { @MainActor [weak self] in
            let move = await Task.detached(priority: .userInitiated) {
                CheckersAI(strength: level).chooseMove(for: snapshot)
            }.value

            let elapsed = Date().timeIntervalSince(started)
            if elapsed < minimumDelay {
                try? await Task.sleep(nanoseconds: UInt64((minimumDelay - elapsed) * 1_000_000_000))
            }

            guard let self, self.aiGeneration == generation else { return }  // reset or opponent changed
            self.isThinking = false
            if let move { self.play(move) }
        }
    }
}
