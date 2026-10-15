import Foundation

private enum Score {
    static let win = 10_000
    static let infinity = 1_000_000
}

extension GameState {
    /// Plays a move that is already known to be legal, skipping the re-validation that
    /// `applying(_:)` does. The AI calls this thousands of times per turn.
    func applyingUnchecked(_ move: Move) -> GameState {
        var newSquares = squares
        guard var piece = newSquares[move.from.row][move.from.col] else { return self }
        newSquares[move.from.row][move.from.col] = nil
        for pos in move.captured { newSquares[pos.row][pos.col] = nil }
        if move.to.row == piece.color.kingRow { piece.isKing = true }
        newSquares[move.to.row][move.to.col] = piece
        return GameState(squares: newSquares, turn: turn.opponent, forcedCapture: forcedCapture)
    }
}

/// A checkers opponent whose strength is a dial from 0 to 100.
///
/// - 0 plays a random legal move every time.
/// - Below about 35 it still plays random moves some of the time.
/// - As the dial goes up it looks further ahead (1 move at the bottom, 12 at the top),
///   gets more thinking time (0.3 to 1.5 seconds), and stops making "almost-best" choices.
/// - 100 is the strongest the search can manage.
struct CheckersAI {
    /// 0 (weakest) ... 100 (strongest)
    let strength: Int

    private var level: Double { Double(min(max(strength, 0), 100)) }

    func chooseMove(for state: GameState) -> Move? {
        let moves = state.legalMoves()
        guard !moves.isEmpty else { return nil }
        if moves.count == 1 { return moves[0] }

        // Weak settings often just play a random legal move.
        let randomChance = max(0, (35 - level) / 35)
        if Double.random(in: 0..<1) < randomChance {
            return moves.randomElement()!
        }

        let maxDepth = Int(level / 100 * 11) + 1                // 1 ... 12 moves ahead
        let timeLimit = 0.3 + level / 100 * 1.2                  // 0.3 ... 1.5 seconds
        let margin = Int(max(0, 85 - level) * 1.5)              // how far from the best move it may stray
        return searchBest(state, moves, maxDepth: maxDepth, timeLimit: timeLimit, margin: margin)
    }

    // MARK: Iterative-deepening alpha-beta search

    /// Searches deeper and deeper until it runs out of depth or time, keeping the result of the
    /// last fully finished depth. `margin` lets weaker settings pick at random among moves that
    /// score within that many points of the best one (100 points is about one man).
    private func searchBest(_ state: GameState, _ moves: [Move], maxDepth: Int, timeLimit: TimeInterval, margin: Int) -> Move {
        let searcher = Searcher(deadline: Date().addingTimeInterval(timeLimit))
        var ordered = moves
        var best = moves.randomElement()!

        for depth in 1...maxDepth {
            var scored: [(move: Move, score: Int)] = []
            var bestScore = -Score.infinity

            for move in ordered {
                // Keep the window just below the best score (minus the margin) so every move
                // that could be chosen is scored exactly.
                let rootAlpha = bestScore == -Score.infinity ? -Score.infinity : bestScore - margin - 1
                let score = -searcher.search(state.applyingUnchecked(move),
                                             depth: depth - 1,
                                             alpha: -Score.infinity,
                                             beta: -rootAlpha)
                if searcher.timedOut { break }
                scored.append((move, score))
                bestScore = max(bestScore, score)
            }

            if searcher.timedOut { break }  // out of time: keep the last fully searched result

            let candidates = scored.filter { $0.score >= bestScore - margin }.map { $0.move }
            best = candidates.randomElement() ?? best

            // Search the best move first next time: faster pruning.
            if let top = scored.max(by: { $0.score < $1.score })?.move,
               let index = ordered.firstIndex(of: top) {
                ordered.swapAt(0, index)
            }
            if bestScore > Score.win / 2 { break }  // found a forced win
        }
        return best
    }

    // MARK: Evaluation

    /// Score for the player whose turn it is: positive is good for them.
    static func evaluate(_ state: GameState) -> Int {
        var redScore = 0
        for row in 0..<8 {
            for col in 0..<8 {
                guard let piece = state[Position(row: row, col: col)] else { continue }
                let centerBonus = 14 - (abs(2 * col - 7) + abs(2 * row - 7))  // 0...12
                var value: Int
                if piece.isKing {
                    value = 175 + centerBonus
                } else {
                    let progress = piece.color == .red ? 7 - row : row  // rows advanced toward promotion
                    value = 100 + progress * 5 + centerBonus / 3
                    if progress == 0 { value += 8 }           // back-row men guard against kings
                    if col == 0 || col == 7 { value += 3 }    // edge pieces can't be jumped
                }
                redScore += piece.color == .red ? value : -value
            }
        }
        return state.turn == .red ? redScore : -redScore
    }

    private final class Searcher {
        let deadline: Date?
        var nodes = 0
        var timedOut = false

        init(deadline: Date?) {
            self.deadline = deadline
        }

        /// Negamax with alpha-beta pruning. Returns the score for the player to move.
        func search(_ state: GameState, depth: Int, alpha: Int, beta: Int) -> Int {
            if timedOut { return 0 }
            nodes += 1
            if nodes & 1023 == 0, let deadline, Date() > deadline {
                timedOut = true
                return 0
            }

            let moves = state.legalMoves()
            if moves.isEmpty {
                return -Score.win - depth  // player to move has lost; faster losses score worse
            }

            var alpha = alpha
            var best = -Score.infinity
            var candidates = moves

            if depth <= 0 {
                // At the end of the search keep looking at captures, so we never judge a
                // position in the middle of an exchange. (Depth-limited to stay quick.)
                let captures = moves.filter { $0.isCapture }
                if captures.isEmpty || depth <= -6 {
                    return CheckersAI.evaluate(state)
                }
                if !state.forcedCapture {
                    // Captures are optional here, so the side to move may simply decline them.
                    best = CheckersAI.evaluate(state)
                    if best >= beta { return best }
                    alpha = max(alpha, best)
                }
                candidates = captures
            }

            for move in candidates {
                let score = -search(state.applyingUnchecked(move), depth: depth - 1, alpha: -beta, beta: -alpha)
                if timedOut { return 0 }
                if score > best { best = score }
                if best > alpha { alpha = best }
                if alpha >= beta { break }
            }
            return best
        }
    }
}
