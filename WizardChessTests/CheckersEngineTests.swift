import XCTest
@testable import WizardChess  // replace with your app's module name

final class CheckersEngineTests: XCTestCase {

    func testOpeningPositionHasSevenMoves() {
        let game = GameState.initial()
        XCTAssertEqual(game.legalMoves().count, 7)
    }

    func testOptionalCaptureAllowsQuietMove() {
        let pieces: [(Position, Piece)] = [
            (Position(row: 4, col: 3), Piece(color: .red)),
            (Position(row: 6, col: 1), Piece(color: .red)),
            (Position(row: 3, col: 2), Piece(color: .black)),
        ]
        // Official rules: only the jump is legal.
        let forced = GameState.custom(pieces, turn: .red)
        XCTAssertTrue(forced.legalMoves().allSatisfy { $0.isCapture })

        // With forced jumps off, the jump and the ordinary moves are all legal.
        let optional = GameState.custom(pieces, turn: .red, forcedCapture: false)
        let moves = optional.legalMoves()
        XCTAssertTrue(moves.contains { $0.isCapture })
        XCTAssertTrue(moves.contains { !$0.isCapture })
    }

    func testForcedCaptureSettingSurvivesMoves() {
        var game = GameState.initial(forcedCapture: false)
        game = game.applying(game.legalMoves()[0])!
        XCTAssertFalse(game.forcedCapture)
    }

    func testBlackMovesFirst() {
        // US rules: black opens the game.
        XCTAssertEqual(GameState.initial().turn, .black)
    }

    func testMenCannotCaptureBackward() {
        // A red man with a black piece behind it (toward red's own side) may not jump backward.
        let game = GameState.custom([
            (Position(row: 4, col: 3), Piece(color: .red)),
            (Position(row: 5, col: 4), Piece(color: .black)),
        ], turn: .red)
        XCTAssertTrue(game.legalMoves().allSatisfy { !$0.isCapture })
    }

    func testKingsMoveOnlyOneSquare() {
        // No flying kings: a lone king has four single steps, never a long slide.
        let game = GameState.custom([
            (Position(row: 3, col: 4), Piece(color: .red, isKing: true)),
        ], turn: .red)
        let moves = game.legalMoves()
        XCTAssertEqual(moves.count, 4)
        XCTAssertTrue(moves.allSatisfy { abs($0.to.row - $0.from.row) == 1 })
    }

    func testCrowningEndsTheJump() {
        // A man that reaches the far row mid-jump is crowned and must stop,
        // even though a king could keep jumping from there.
        let game = GameState.custom([
            (Position(row: 2, col: 1), Piece(color: .red)),
            (Position(row: 1, col: 2), Piece(color: .black)),
            (Position(row: 1, col: 4), Piece(color: .black)),
        ], turn: .red)
        let moves = game.legalMoves()
        XCTAssertEqual(moves.count, 1)
        XCTAssertEqual(moves[0].captured.count, 1)
        XCTAssertEqual(moves[0].to, Position(row: 0, col: 3))
    }

    func testCaptureIsMandatory() {
        // Red can jump the black piece, so the quiet move with the other red piece is not allowed.
        let game = GameState.custom([
            (Position(row: 4, col: 3), Piece(color: .red)),
            (Position(row: 6, col: 1), Piece(color: .red)),
            (Position(row: 3, col: 2), Piece(color: .black)),
        ], turn: .red)

        let moves = game.legalMoves()
        XCTAssertEqual(moves.count, 1)
        XCTAssertEqual(moves[0].captured, [Position(row: 3, col: 2)])
        XCTAssertEqual(moves[0].to, Position(row: 2, col: 1))
    }

    func testMultiJump() {
        let game = GameState.custom([
            (Position(row: 6, col: 1), Piece(color: .red)),
            (Position(row: 5, col: 2), Piece(color: .black)),
            (Position(row: 3, col: 4), Piece(color: .black)),
        ], turn: .red)

        let moves = game.legalMoves()
        XCTAssertEqual(moves.count, 1)
        XCTAssertEqual(moves[0].path.count, 3)
        XCTAssertEqual(moves[0].captured.count, 2)
        XCTAssertEqual(moves[0].to, Position(row: 2, col: 5))
    }

    func testPromotionToKing() {
        let game = GameState.custom([
            (Position(row: 1, col: 2), Piece(color: .red)),
            (Position(row: 6, col: 5), Piece(color: .black)),
        ], turn: .red)

        let move = Move(path: [Position(row: 1, col: 2), Position(row: 0, col: 1)], captured: [])
        let next = game.applying(move)
        XCTAssertEqual(next?[Position(row: 0, col: 1)]?.isKing, true)
    }

    func testIllegalMoveIsRejected() {
        let game = GameState.initial()
        let bogus = Move(path: [Position(row: 5, col: 0), Position(row: 3, col: 0)], captured: [])
        XCTAssertNil(game.applying(bogus))
    }

    func testPlayerWithNoPiecesLoses() {
        let game = GameState.custom([
            (Position(row: 4, col: 3), Piece(color: .red)),
        ], turn: .black)
        XCTAssertEqual(game.winner, .red)
    }
}
