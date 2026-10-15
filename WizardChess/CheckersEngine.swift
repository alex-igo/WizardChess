import Foundation

// MARK: - Basic types

enum PieceColor {
    case red    // starts at the bottom (rows 5-7), moves toward row 0
    case black  // starts at the top (rows 0-2), moves toward row 7

    var opponent: PieceColor { self == .red ? .black : .red }

    /// Row direction a regular (non-king) piece moves in.
    var forward: Int { self == .red ? -1 : 1 }

    /// The row where a man of this color is crowned.
    var kingRow: Int { self == .red ? 0 : 7 }
}

struct Piece: Equatable {
    let color: PieceColor
    var isKing: Bool = false
}

struct Position: Hashable {
    let row: Int
    let col: Int

    var isOnBoard: Bool { (0..<8).contains(row) && (0..<8).contains(col) }
}

/// A full turn for one player: a single step, or a chain of jumps.
/// `path` starts at the piece's origin and ends at its final square.
struct Move: Equatable {
    let path: [Position]
    let captured: [Position]

    var from: Position { path.first! }
    var to: Position { path.last! }
    var isCapture: Bool { !captured.isEmpty }
}

// MARK: - Game state

struct GameState {
    private(set) var squares: [[Piece?]]
    private(set) var turn: PieceColor

    /// Official US rules force you to jump when you can. With this off, captures are optional
    /// (a common house rule): jumps are listed alongside ordinary moves and you may pick either.
    let forcedCapture: Bool

    init(squares: [[Piece?]], turn: PieceColor, forcedCapture: Bool = true) {
        self.squares = squares
        self.turn = turn
        self.forcedCapture = forcedCapture
    }

    /// Standard starting position. Dark squares are the ones where (row + col) is odd, so each
    /// player has a dark square in their lower-left corner. Black moves first in official US rules; `firstMove` lets a game start with red instead.
    static func initial(forcedCapture: Bool = true, firstMove: PieceColor = .black) -> GameState {
        var squares = Array(repeating: Array(repeating: Piece?.none, count: 8), count: 8)
        for row in 0..<8 {
            for col in 0..<8 where (row + col) % 2 == 1 {
                if row < 3 { squares[row][col] = Piece(color: .black) }
                if row > 4 { squares[row][col] = Piece(color: .red) }
            }
        }
        return GameState(squares: squares, turn: firstMove, forcedCapture: forcedCapture)
    }

    /// Handy for tests and puzzles: build a position from a list of pieces.
    static func custom(_ pieces: [(Position, Piece)], turn: PieceColor, forcedCapture: Bool = true) -> GameState {
        var squares = Array(repeating: Array(repeating: Piece?.none, count: 8), count: 8)
        for (pos, piece) in pieces { squares[pos.row][pos.col] = piece }
        return GameState(squares: squares, turn: turn, forcedCapture: forcedCapture)
    }

    subscript(pos: Position) -> Piece? {
        pos.isOnBoard ? squares[pos.row][pos.col] : nil
    }

    // MARK: Rules

    /// All legal moves for the player whose turn it is.
    /// With forced captures (the official rule), if any capture exists only captures are returned.
    /// With forced captures off, captures and ordinary moves are all returned.
    func legalMoves() -> [Move] {
        var captures: [Move] = []
        var steps: [Move] = []

        for row in 0..<8 {
            for col in 0..<8 {
                let pos = Position(row: row, col: col)
                guard let piece = self[pos], piece.color == turn else { continue }
                captures += captureSequences(from: pos, piece: piece)
                steps += stepMoves(from: pos, piece: piece)
            }
        }
        if forcedCapture {
            return captures.isEmpty ? steps : captures
        }
        return captures + steps
    }

    /// Returns the new state after playing `move`, or nil if the move isn't legal.
    func applying(_ move: Move) -> GameState? {
        guard legalMoves().contains(move), var piece = self[move.from] else { return nil }

        var newSquares = squares
        newSquares[move.from.row][move.from.col] = nil
        for pos in move.captured { newSquares[pos.row][pos.col] = nil }
        if move.to.row == piece.color.kingRow { piece.isKing = true }
        newSquares[move.to.row][move.to.col] = piece

        return GameState(squares: newSquares, turn: turn.opponent, forcedCapture: forcedCapture)
    }

    /// The winner, or nil while the game is still going.
    /// A player who has no legal moves (no pieces, or all blocked) loses.
    var winner: PieceColor? {
        legalMoves().isEmpty ? turn.opponent : nil
    }

    // MARK: Move generation

    private func directions(for piece: Piece) -> [(row: Int, col: Int)] {
        let f = piece.color.forward
        return piece.isKing
            ? [(f, -1), (f, 1), (-f, -1), (-f, 1)]
            : [(f, -1), (f, 1)]
    }

    private func stepMoves(from pos: Position, piece: Piece) -> [Move] {
        directions(for: piece).compactMap { d in
            let target = Position(row: pos.row + d.row, col: pos.col + d.col)
            guard target.isOnBoard, self[target] == nil else { return nil }
            return Move(path: [pos, target], captured: [])
        }
    }

    /// Depth-first search for every complete jump chain starting at `start`.
    /// Captured pieces stay on the board until the move ends, so they can't be jumped twice.
    /// A man that reaches the king row mid-jump is crowned and its turn ends.
    private func captureSequences(from start: Position, piece: Piece) -> [Move] {
        var results: [Move] = []

        func explore(at pos: Position, isKing: Bool, path: [Position], captured: [Position]) {
            var extended = false
            let current = Piece(color: piece.color, isKing: isKing)

            for d in directions(for: current) {
                let over = Position(row: pos.row + d.row, col: pos.col + d.col)
                let land = Position(row: pos.row + 2 * d.row, col: pos.col + 2 * d.col)

                guard land.isOnBoard,
                      !captured.contains(over),
                      let victim = self[over], victim.color != piece.color,
                      self[land] == nil || land == start  // the mover has vacated its start square
                else { continue }

                extended = true
                let newPath = path + [land]
                let newCaptured = captured + [over]

                if !isKing && land.row == piece.color.kingRow {
                    results.append(Move(path: newPath, captured: newCaptured))  // crowned: turn ends
                } else {
                    explore(at: land, isKing: isKing, path: newPath, captured: newCaptured)
                }
            }

            if !extended && !captured.isEmpty {
                results.append(Move(path: path, captured: captured))
            }
        }

        explore(at: start, isKing: piece.isKing, path: [start], captured: [])
        return results
    }
}
