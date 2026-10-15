import SwiftUI

/// A flat SwiftUI board driven by the same GameViewModel as the 3D scene.
/// Handy for testing the rules quickly.
struct Board2DView: View {
    @ObservedObject var viewModel: GameViewModel

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let cell = side / 8

            // When you play black against the computer the board is turned around so your pieces are nearest you.
            let flipped = viewModel.boardFlipped
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { displayRow in
                    HStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { displayCol in
                            squareView(row: flipped ? 7 - displayRow : displayRow,
                                       col: flipped ? 7 - displayCol : displayCol,
                                       size: cell)
                        }
                    }
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func squareView(row: Int, col: Int, size: CGFloat) -> some View {
        let pos = Position(row: row, col: col)
        let isDark = (row + col) % 2 == 1
        let isSelected = viewModel.selected == pos
        let isTarget = viewModel.movesForSelected.contains { $0.to == pos }
        let isHintFrom = viewModel.hint?.from == pos
        let isHintStep = viewModel.hint?.path.dropFirst().contains(pos) ?? false

        return ZStack {
            Rectangle()
                .fill(isDark ? Color(red: 0.30, green: 0.18, blue: 0.12)
                             : Color(red: 0.93, green: 0.92, blue: 0.89))

            if isSelected {
                Rectangle().stroke(Color.yellow, lineWidth: 4)
            }
            if isHintFrom {
                Rectangle().stroke(Color.cyan, lineWidth: 4)
            }
            if isHintStep {
                Circle()
                    .stroke(Color.cyan, lineWidth: 4)
                    .frame(width: size * 0.5, height: size * 0.5)
            }
            if isTarget {
                Circle()
                    .fill(Color.green.opacity(0.6))
                    .frame(width: size * 0.35, height: size * 0.35)
            }
            if let piece = viewModel.state[pos] {
                Circle()
                    .fill(piece.color == .red ? Color(red: 0.78, green: 0.08, blue: 0.10)
                                              : Color(red: 0.10, green: 0.10, blue: 0.12))
                    .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 2))
                    .padding(size * 0.12)
                if piece.isKing {
                    Text("♛")
                        .font(.system(size: size * 0.45))
                        .foregroundStyle(Color.yellow)
                }
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .onTapGesture { viewModel.tap(pos) }
    }
}
