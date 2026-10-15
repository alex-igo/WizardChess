import SwiftUI
import SceneKit

/// Hosts the SceneKit board inside SwiftUI. Handles taps (select / move), one-finger drag
/// (orbit the camera), and pinch (zoom).
struct CheckersSceneView: UIViewRepresentable {
    @ObservedObject var viewModel: GameViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = context.coordinator.board.scene
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = .clear   // the Ocean theme shows animated fish through the scene
        view.isOpaque = false
        view.allowsCameraControl = false

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)

        // Drag with one finger to orbit the camera around the board.
        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)

        // Pinch to zoom.
        let pinch = UIPinchGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.handlePinch(_:)))
        view.addGestureRecognizer(pinch)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.viewModel = viewModel
        context.coordinator.update()
    }

    final class Coordinator: NSObject {
        var viewModel: GameViewModel
        let board = BoardScene()
        private var lastMoveCount = 0
        private var lastFlipped = false
        private var lastSharkStage: SharkStage = .none

        init(viewModel: GameViewModel) {
            self.viewModel = viewModel
            self.lastMoveCount = viewModel.moveCount
            self.lastFlipped = viewModel.boardFlipped
            board.setViewpoint(flipped: lastFlipped)
            board.applyBackground(theme: viewModel.theme, customHex: viewModel.customBackgroundHex)
        }

        /// Pushes the latest game state into the scene, animating if a new move was just played.
        func update() {
            board.hint = viewModel.hint
            board.applyBackground(theme: viewModel.theme, customHex: viewModel.customBackgroundHex)
            if viewModel.boardFlipped != lastFlipped {
                lastFlipped = viewModel.boardFlipped
                board.setViewpoint(flipped: lastFlipped)  // you switched sides: view from your side
            }
            if viewModel.moveCount != lastMoveCount {
                lastMoveCount = viewModel.moveCount
                if let move = viewModel.lastMove {
                    board.animate(move: move,
                                  to: viewModel.state,
                                  selected: viewModel.selected,
                                  moves: viewModel.movesForSelected)
                    updateShark()
                    return
                }
                board.cancelAnimation()  // game was reset
                board.setViewpoint(flipped: lastFlipped)  // and the camera returns to its centred start
            }
            board.sync(state: viewModel.state,
                       selected: viewModel.selected,
                       moves: viewModel.movesForSelected)
            updateShark()
        }

        /// Starts or ends the Ocean shark scene when the game's shark stage changes.
        private func updateShark() {
            let stage = viewModel.sharkStage
            guard stage != lastSharkStage else { return }
            lastSharkStage = stage
            switch stage {
            case .stalking:
                let model = viewModel
                board.startShark(state: model.state) { model.sharkFinishedEating() }
            case .none:
                board.clearShark(flipped: viewModel.boardFlipped)
            case .attacking, .done:
                break
            }
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            gesture.setTranslation(.zero, in: gesture.view)
            let sensitivity: Float = 0.01
            // Drag right to spin the board right; drag down to look more from above.
            board.orbit(deltaYaw: -Float(translation.x) * sensitivity,
                        deltaPitch: Float(translation.y) * sensitivity * 0.6)
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            board.zoom(scale: Float(gesture.scale))
            gesture.scale = 1
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard !board.isAnimating, let view = gesture.view as? SCNView else { return }
            let point = gesture.location(in: view)
            // Results come back nearest-first; use the first one that belongs to a square or piece.
            for hit in view.hitTest(point, options: nil) {
                if let position = boardPosition(for: hit.node) {
                    viewModel.tap(position)
                    return
                }
            }
        }

        /// Walks up from a tapped node to find a name like "sq-3-4" or "pc-3-4".
        private func boardPosition(for node: SCNNode) -> Position? {
            var current: SCNNode? = node
            while let n = current {
                if let name = n.name {
                    let parts = name.split(separator: "-")
                    if parts.count == 3, parts[0] == "sq" || parts[0] == "pc",
                       let row = Int(parts[1]), let col = Int(parts[2]) {
                        return Position(row: row, col: col)
                    }
                }
                current = n.parent
            }
            return nil
        }
    }
}
