import SceneKit
import UIKit

/// Builds and updates the 3D scene: the board, lights, camera, pieces, and all the animation.
/// Board coordinates map to the scene like this: each square is 1 x 1 unit, the board is
/// centered on the origin, column grows along +x and row grows along +z. Red's side
/// (rows 5-7) starts nearest the camera.
final class BoardScene {
    let scene = SCNScene()

    private let piecesNode = SCNNode()
    private let highlightsNode = SCNNode()

    // Destruction effects live here so they keep playing after the board is redrawn.
    private let effectsNode = SCNNode()
    // One permanent flash light, reused for every capture. Adding or removing lights
    // mid-game makes SceneKit recompile its shaders, which shows up as a stutter.
    private let flashNode = SCNNode()
    private let ambientNode = SCNNode()

    // The frame and squares, remembered so the shark can eat them and a new game can bring them back.
    private var boardNodes: [(node: SCNNode, position: SCNVector3)] = []
    private var sharkRoot: SCNNode?
    private var currentTheme: BackgroundTheme = .starryNight
    // The little cubes a square breaks into when the spaceship shoots it.
    private var pixelTiles: [String: [SCNNode]] = [:]

    // MARK: Animation bookkeeping

    private struct QueuedMove {
        let move: Move
        let newState: GameState
        let selected: Position?
        let moves: [Move]
    }

    private var displayedState: GameState?
    private(set) var isAnimating = false
    private var animationToken = 0
    private var queue: [QueuedMove] = []

    private let hopDuration: TimeInterval = 0.4
    /// Chains of jumps are slower and pause briefly between jumps.
    private let multiJumpHopDuration: TimeInterval = 0.75
    private let multiJumpPause: TimeInterval = 0.3

    // MARK: Camera rig
    // The camera sits on a two-part rig so it can orbit the board: `yawNode` spins around the
    // vertical axis, `pitchNode` tilts up and down, and the camera hangs `cameraDistance` away.

    private var cameraNode: SCNNode?
    private let yawNode = SCNNode()
    private let pitchNode = SCNNode()
    private var cameraDistance: Float = 12.2
    private var cameraBasePosition: SCNVector3 { SCNVector3(0, 0, cameraDistance) }
    private var yaw: Float = 0
    /// Default camera tilt in degrees above the board's surface (90 = straight down, 0 = level with it).
    private static let defaultPitchDegrees: Float = 35
    private var pitch: Float = BoardScene.defaultPitchDegrees * Float.pi / 180
    private let minPitch: Float = 5 * Float.pi / 180
    private let maxPitch: Float = 88 * Float.pi / 180
    private let minDistance: Float = 7
    private let maxDistance: Float = 20

    // MARK: Look and feel (tweak these freely)

    private let lightSquareColor = UIColor(red: 0.93, green: 0.92, blue: 0.89, alpha: 1)
    private let darkSquareColor = UIColor(red: 0.22, green: 0.13, blue: 0.09, alpha: 1)
    private let redPieceColor = UIColor(red: 0.78, green: 0.08, blue: 0.10, alpha: 1)
    private let blackPieceColor = UIColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1)
    private let selectionColor = UIColor(red: 1.0, green: 0.82, blue: 0.25, alpha: 1)
    private let moveTargetColor = UIColor(red: 0.30, green: 0.90, blue: 0.55, alpha: 1)
    private let hintColor = UIColor(red: 0.35, green: 0.75, blue: 1.0, alpha: 1)

    /// The suggested move to highlight (set by the view before each redraw).
    var hint: Move?

    init() {
        scene.background.contents = UIColor(red: 0.03, green: 0.03, blue: 0.05, alpha: 1)
        scene.rootNode.addChildNode(piecesNode)
        scene.rootNode.addChildNode(highlightsNode)
        scene.rootNode.addChildNode(effectsNode)

        let flashLight = SCNLight()
        flashLight.type = .omni
        flashLight.color = UIColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1)
        flashLight.intensity = 0
        flashLight.attenuationStartDistance = 0.5
        flashLight.attenuationEndDistance = 4
        flashNode.light = flashLight
        flashNode.position = SCNVector3(0, 0.8, 0)
        scene.rootNode.addChildNode(flashNode)

        buildBoard()
        buildLights()
        buildCamera()
    }

    // MARK: Coordinates

    static func worldPosition(row: Int, col: Int, y: CGFloat = 0) -> SCNVector3 {
        SCNVector3(Float(col) - 3.5, Float(y), Float(row) - 3.5)
    }

    // MARK: Static scene setup

    private func buildBoard() {
        // Dark frame under and around the squares
        let frame = SCNBox(width: 8.7, height: 0.3, length: 8.7, chamferRadius: 0.05)
        frame.firstMaterial = material(color: UIColor(red: 0.12, green: 0.07, blue: 0.05, alpha: 1),
                                       roughness: 0.5, metalness: 0.0)
        let frameNode = SCNNode(geometry: frame)
        frameNode.position = SCNVector3(0, -0.25, 0)
        scene.rootNode.addChildNode(frameNode)
        boardNodes.append((frameNode, frameNode.position))

        // Invisible floor so flying shards land on the board instead of falling through it.
        let floorShape = SCNPhysicsShape(geometry: SCNBox(width: 8.7, height: 0.1, length: 8.7, chamferRadius: 0),
                                         options: nil)
        let floor = SCNNode()
        floor.position = SCNVector3(0, -0.05, 0)
        floor.physicsBody = SCNPhysicsBody(type: .static, shape: floorShape)
        floor.physicsBody?.friction = 0.7
        floor.physicsBody?.restitution = 0.3
        scene.rootNode.addChildNode(floor)

        for row in 0..<8 {
            for col in 0..<8 {
                let square = SCNBox(width: 1, height: 0.2, length: 1, chamferRadius: 0)
                let isDark = (row + col) % 2 == 1
                square.firstMaterial = material(color: isDark ? darkSquareColor : lightSquareColor,
                                                roughness: 0.35, metalness: 0.0)
                let node = SCNNode(geometry: square)
                node.name = "sq-\(row)-\(col)"
                node.position = BoardScene.worldPosition(row: row, col: col, y: -0.1)
                scene.rootNode.addChildNode(node)
                boardNodes.append((node, node.position))
            }
        }
    }

    private func buildLights() {
        ambientNode.light = SCNLight()
        ambientNode.light?.type = .ambient
        ambientNode.light?.intensity = 350
        ambientNode.light?.color = UIColor(white: 0.8, alpha: 1)
        scene.rootNode.addChildNode(ambientNode)

        let spot = SCNNode()
        let light = SCNLight()
        light.type = .spot
        light.intensity = 2000
        light.color = UIColor(white: 1.0, alpha: 1)
        light.spotInnerAngle = 30
        light.spotOuterAngle = 90
        light.castsShadow = true
        light.shadowRadius = 6
        light.shadowSampleCount = 8
        light.shadowColor = UIColor(white: 0, alpha: 0.6)
        spot.light = light
        spot.position = SCNVector3(3, 10, 5)
        spot.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(spot)
    }

    private func buildCamera() {
        let camera = SCNCamera()
        // Fit the board's width to the screen's width, whatever the phone's shape.
        camera.projectionDirection = .horizontal
        camera.fieldOfView = 52
        camera.zNear = 0.1
        camera.zFar = 100
        let node = SCNNode()
        node.camera = camera
        pitchNode.addChildNode(node)
        yawNode.addChildNode(pitchNode)
        scene.rootNode.addChildNode(yawNode)
        cameraNode = node
        applyOrbit()
    }

    // MARK: Background

    private var appliedBackground = ""

    /// Sets the backdrop. Pictures are wrapped around the whole scene like a sky, so as you orbit
    /// the board the stars move behind it. A custom colour is just a solid fill.
    func applyBackground(theme: BackgroundTheme, customHex: String) {
        currentTheme = theme
        let key = theme == .custom ? "custom|\(customHex)" : theme.rawValue
        guard key != appliedBackground else { return }
        appliedBackground = key

        if theme == .ocean || theme == .snowyNight {
            // Transparent, so the animated fish (or falling snow) behind the 3D view shows through.
            scene.background.contents = UIColor.clear
        } else if theme == .custom {
            scene.background.contents = UIColor(hex: customHex)
        } else {
            scene.background.contents = SkyRenderer.image(for: theme, customHex: customHex,
                                                          size: CGSize(width: 2048, height: 1024))
        }
    }

    // MARK: Camera control

    /// Spins and tilts the camera around the board. Angles are in radians.
    func orbit(deltaYaw: Float, deltaPitch: Float) {
        yaw += deltaYaw
        pitch = min(max(pitch + deltaPitch, minPitch), maxPitch)
        applyOrbit()
    }

    /// Views the board from red's side (default) or from black's side.
    func setViewpoint(flipped: Bool) {
        yaw = flipped ? Float.pi : 0
        pitch = BoardScene.defaultPitchDegrees * Float.pi / 180   // back to the starting tilt and zoom
        cameraDistance = 12.2
        applyOrbit()
    }

    /// Moves the camera closer (scale > 1) or farther (scale < 1).
    func zoom(scale: Float) {
        guard scale > 0 else { return }
        cameraDistance = min(max(cameraDistance / scale, minDistance), maxDistance)
        applyOrbit()
    }

    private func applyOrbit() {
        yawNode.eulerAngles = SCNVector3(0, yaw, 0)
        pitchNode.eulerAngles = SCNVector3(-pitch, 0, 0)
        cameraNode?.position = cameraBasePosition
    }

    // MARK: Updating from game state

    /// Brings the scene in line with the game (no animation). Ignored while a move is animating,
    /// because the animation redraws the final position itself when it finishes.
    func sync(state: GameState, selected: Position?, moves: [Move]) {
        guard !isAnimating else { return }
        draw(state: state, selected: selected, moves: moves)
    }

    /// Stops any running animation and forgets queued ones (used when the game is reset).
    func cancelAnimation() {
        animationToken += 1
        isAnimating = false
        queue.removeAll()
    }

    /// Plays `move` as an animation: the piece hops along its path, and each jumped piece
    /// shatters as the jumper passes over it. When it ends the scene is redrawn from the final
    /// game state (which also handles crowning). Moves that arrive mid-animation wait their turn.
    func animate(move: Move, to newState: GameState, selected: Position?, moves: [Move]) {
        if isAnimating {
            queue.append(QueuedMove(move: move, newState: newState, selected: selected, moves: moves))
            return
        }
        guard let old = displayedState, let moving = old[move.from] else {
            draw(state: newState, selected: selected, moves: moves)
            return
        }

        animationToken += 1
        let token = animationToken
        isAnimating = true
        highlightsNode.childNodes.forEach { $0.removeFromParentNode() }
        piecesNode.childNodes.forEach { $0.removeFromParentNode() }

        // Draw the position as it was before the move, except for the moving piece.
        var victims: [Position: SCNNode] = [:]
        for row in 0..<8 {
            for col in 0..<8 {
                let pos = Position(row: row, col: col)
                guard pos != move.from, let piece = old[pos] else { continue }
                let node = makePiece(piece, at: pos)
                piecesNode.addChildNode(node)
                if move.captured.contains(pos) { victims[pos] = node }
            }
        }
        let mover = makePiece(moving, at: move.from)
        piecesNode.addChildNode(mover)

        // Multi-jumps play in slow motion, with a short beat between jumps, so you can follow each capture.
        let isMultiJump = move.path.count > 2
        let hopTime = isMultiJump ? multiJumpHopDuration : hopDuration
        let beat = isMultiJump ? multiJumpPause : 0

        var steps: [SCNAction] = []
        var elapsed: TimeInterval = 0
        for i in 0..<(move.path.count - 1) {
            let a = move.path[i]
            let b = move.path[i + 1]
            let height: Float = move.isCapture ? 0.8 : 0.3
            steps.append(hopAction(from: BoardScene.worldPosition(row: a.row, col: a.col),
                                   to: BoardScene.worldPosition(row: b.row, col: b.col),
                                   height: height,
                                   duration: hopTime))

            // The jumped piece shatters as the jumper passes over it.
            if move.isCapture, i < move.captured.count,
               let victim = victims[move.captured[i]],
               let victimPiece = old[move.captured[i]] {
                let direction = SCNVector3(Float(b.col - a.col) / 2, 0, Float(b.row - a.row) / 2)
                schedule(after: elapsed + hopTime * 0.5, token: token) {
                    self.shatter(victim, piece: victimPiece, direction: direction)
                    Feedback.capture(isKing: victimPiece.isKing)
                }
            }

            // Landing thud at the end of each hop.
            schedule(after: elapsed + hopTime, token: token) {
                Feedback.landing()
            }
            elapsed += hopTime
            if beat > 0, i < move.path.count - 2 {
                steps.append(.wait(duration: beat))
                elapsed += beat
            }
        }
        mover.runAction(.sequence(steps))

        let crowned = !moving.isKing && newState[move.to]?.isKing == true
        if crowned {
            schedule(after: elapsed + 0.08, token: token) {
                Feedback.crown()
            }
        }

        // When everything has played out, draw the true final position and start the next queued move.
        schedule(after: elapsed + 0.35, token: token) {
            self.isAnimating = false
            self.draw(state: newState, selected: selected, moves: moves)
            if newState.winner != nil { Feedback.gameOver() }
            if !self.queue.isEmpty {
                let next = self.queue.removeFirst()
                self.animate(move: next.move, to: next.newState, selected: next.selected, moves: next.moves)
            }
        }
    }

    /// Runs `work` on the main thread after `delay` seconds, unless the animation was cancelled meanwhile.
    private func schedule(after delay: TimeInterval, token: Int, _ work: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard self.animationToken == token else { return }
            work()
        }
    }

    private func hopAction(from a: SCNVector3, to b: SCNVector3, height: Float, duration: TimeInterval) -> SCNAction {
        SCNAction.customAction(duration: duration) { node, elapsed in
            let t = min(max(Float(elapsed) / Float(duration), 0), 1)
            let eased = t * t * (3 - 2 * t)
            node.position = SCNVector3(a.x + (b.x - a.x) * eased,
                                       sin(t * Float.pi) * height,
                                       a.z + (b.z - a.z) * eased)
        }
    }

    /// Redraws pieces and highlights to match the game.
    private func draw(state: GameState, selected: Position?, moves: [Move]) {
        displayedState = state
        piecesNode.childNodes.forEach { $0.removeFromParentNode() }
        highlightsNode.childNodes.forEach { $0.removeFromParentNode() }

        for row in 0..<8 {
            for col in 0..<8 {
                let pos = Position(row: row, col: col)
                if let piece = state[pos] {
                    piecesNode.addChildNode(makePiece(piece, at: pos))
                }
            }
        }

        if let selected {
            highlightsNode.addChildNode(makeDisc(at: selected, color: selectionColor, radius: 0.46))
        }
        for move in moves {
            highlightsNode.addChildNode(makeDisc(at: move.to, color: moveTargetColor, radius: 0.34))
        }

        // The hint: a blue ring on the piece to move, and blue discs along its path.
        if let hint {
            highlightsNode.addChildNode(makeDisc(at: hint.from, color: hintColor, radius: 0.52, y: 0.02))
            for step in hint.path.dropFirst() {
                highlightsNode.addChildNode(makeDisc(at: step, color: hintColor, radius: 0.38, y: 0.02))
            }
        }
    }


    // MARK: Shark attack (Ocean theme)

    /// Runs the whole shark sequence as one timeline: it circles the board for 5 seconds while the camera
    /// backs away, then sweeps across three times, chewing up every piece and square it reaches.
    /// `onFinished` is called when the board has been eaten. Call after the board has been drawn.
    func startShark(state liveState: GameState, onFinished: @escaping @MainActor () -> Void) {
        guard sharkRoot == nil else { print("[Attack] not starting: an attacker is already on the board"); return }
        let state = displayedState ?? liveState

        animationToken += 1
        let token = animationToken
        isAnimating = true          // freezes redrawing and taps until the next game
        queue.removeAll()
        highlightsNode.childNodes.forEach { $0.removeFromParentNode() }

        let isShip = currentTheme == .space
        let dragonKind: DragonKind? = currentTheme == .sunset ? .fire : (currentTheme == .snowyNight ? .ice : nil)
        let isDragon = dragonKind != nil
        print("[Attack] starting, theme: \(currentTheme.rawValue), spaceship: \(isShip), dragon: \(isDragon)")
        let path = SharkRig.makePath()
        let headings = SharkRig.headings(for: path)
        let flyHeight: Float = isShip ? SpaceshipRig.height : (isDragon ? DragonRig.height : SharkRig.height)
        let reach: Float = isShip ? SpaceshipRig.reach : (isDragon ? DragonRig.groundReach : SharkRig.noseOffset)

        // The attacker: the shark in the Ocean theme, the spaceship in Outer Space.
        let sharkModel: (root: SCNNode, jaw: SCNNode, tail: SCNNode)? = (isShip || isDragon) ? nil : SharkRig.makeModel()
        let shipModel: SpaceshipRig.Model? = isShip ? SpaceshipRig.makeModel() : nil
        let dragonModel: DragonRig.Model? = dragonKind.map { DragonRig.makeModel(kind: $0) }
        guard let shark = sharkModel?.root ?? shipModel?.root ?? dragonModel?.root else { return }
        let start = path[0]
        shark.position = SCNVector3(start.x, flyHeight, start.y)
        scene.rootNode.addChildNode(shark)
        sharkRoot = shark

        // Following the path, with a little side-to-side wobble (the ship also banks into turns and bobs).
        let duration = Double(path.count) / SharkRig.frameRate
        shark.runAction(.customAction(duration: duration) { node, elapsed in
            let i = min(Int(Double(elapsed) * SharkRig.frameRate), path.count - 1)
            if let ship = shipModel {
                let ahead = min(i + 12, path.count - 1)
                var turn: Float = headings[ahead] - headings[i]
                if turn > Float.pi { turn -= 2 * Float.pi }
                if turn < -Float.pi { turn += 2 * Float.pi }
                let bank: Float = max(-0.5, min(0.5, turn * 2.0))
                let bob: Float = 0.08 * sin(Float(elapsed) * 3)
                node.position = SCNVector3(path[i].x, flyHeight + bob, path[i].y)
                node.eulerAngles = SCNVector3(0, headings[i], 0)
                ship.body.eulerAngles = SCNVector3(bank, 0, 0.04 * sin(Float(elapsed) * 2))
            } else if let dragon = dragonModel {
                let ahead = min(i + 12, path.count - 1)
                var turn: Float = headings[ahead] - headings[i]
                if turn > Float.pi { turn -= 2 * Float.pi }
                if turn < -Float.pi { turn += 2 * Float.pi }
                let bank: Float = max(-0.5, min(0.5, turn * 2.0))
                let bob: Float = 0.12 * sin(Float(elapsed) * 2.2)
                node.position = SCNVector3(path[i].x, flyHeight + bob, path[i].y)
                node.eulerAngles = SCNVector3(0, headings[i], 0)
                dragon.body.eulerAngles = SCNVector3(bank, 0, 0)
                let phase: Double = Double(elapsed) / DragonRig.flapPeriod * 2 * Double.pi
                dragon.mesh.morpher?.setWeight(CGFloat(0.5 + 0.5 * sin(phase)), forTargetAt: 0)
            } else {
                let wobble: Float = 0.07 * sin(Float(elapsed) * 7)
                let sinceAttack = Float(elapsed) - Float(SharkRig.stalkDuration)
                let noseLift: Float = sinceAttack > 0 ? 0.1 * max(0, sin(sinceAttack * 10.47)) : 0   // head rises with each bite
                node.position = SCNVector3(path[i].x, flyHeight, path[i].y)
                node.eulerAngles = SCNVector3(0, headings[i] + wobble, noseLift)
            }
        })
        sharkModel?.tail.runAction(.repeatForever(.sequence([
            .rotateTo(x: 0, y: 0.45, z: 0, duration: 0.3),
            .rotateTo(x: 0, y: -0.45, z: 0, duration: 0.3)
        ])))

        // The room darkens while it circles.
        ambientNode.runAction(.customAction(duration: SharkRig.stalkDuration) { node, elapsed in
            node.light?.intensity = 350 - 230 * elapsed / CGFloat(SharkRig.stalkDuration)
        })

        // The camera slowly backs away while the shark circles.
        let startDistance = cameraDistance
        let farDistance = max(startDistance, 16.5)
        Task { @MainActor in
            let steps = 60
            for i in 1...steps {
                try? await Task.sleep(nanoseconds: 80_000_000)
                guard self.animationToken == token else { return }
                self.cameraDistance = startDistance + (farDistance - startDistance) * Float(i) / Float(steps)
                self.applyOrbit()
            }
        }

        // From the moment it attacks: jaws snapping and a trail of stardust from its mouth.
        let attackTime = SharkRig.stalkDuration
        schedule(after: attackTime, token: token) {
            if let model = sharkModel {
                model.jaw.runAction(.repeatForever(.sequence([
                    .rotateTo(x: 0, y: 0, z: -0.85, duration: 0.25),   // gape
                    .rotateTo(x: 0, y: 0, z: 0, duration: 0.07),       // snap
                    .wait(duration: 0.28)
                ])))
            }
            if let kind = dragonKind {
                shark.addChildNode(DragonRig.makeBreath(kind: kind))
            }
            if !isShip && !isDragon {
                let trail = self.makeStardust(birthRate: 160, lifeSpan: 1.4, velocity: 0.5, continuous: true)
                let emitter = SCNNode()
                emitter.position = SCNVector3(2.9, -0.1, 0)
                emitter.addParticleSystem(trail)
                shark.addChildNode(emitter)
            }
        }

        var lastBite = attackTime
        if isShip {
            lastBite = scheduleShipAttack(state: state, path: path, headings: headings,
                                          flyHeight: flyHeight, token: token)
        } else {
        // Work out when the shark's nose reaches each square and piece, and schedule the bite.
        let noses: [SIMD2<Float>] = path.indices.map { i in
            let h: Float = headings[i]
            let noseX: Float = path[i].x + cos(h) * reach
            let noseZ: Float = path[i].y - sin(h) * reach
            return SIMD2<Float>(noseX, noseZ)
        }
        for row in 0..<8 {
            for col in 0..<8 {
                let x = Float(col) - 3.5
                let z = Float(row) - 3.5
                var frame = path.count - 1
                for i in SharkRig.attackStartFrame..<path.count {
                    let dx = noses[i].x - x, dz = noses[i].y - z
                    if dx * dx + dz * dz < SharkRig.biteRadius * SharkRig.biteRadius { frame = i; break }
                }
                let when = Double(frame) / SharkRig.frameRate
                lastBite = max(lastBite, when)
                let heading = headings[frame]
                let direction = SCNVector3(cos(heading), 0, -sin(heading))
                let position = Position(row: row, col: col)

                if let piece = state[position] {
                    schedule(after: when, token: token) {
                        guard let node = self.piecesNode.childNode(withName: "pc-\(row)-\(col)", recursively: false) else { return }
                        if let kind = dragonKind {
                            self.elementBurst(at: node.position, kind: kind)
                        } else {
                            self.stardust(at: node.position)
                        }
                        self.shatter(node, piece: piece, direction: direction)
                        Feedback.capture(isKing: piece.isKing)
                    }
                }
                schedule(after: when + 0.1, token: token) {
                    guard let tile = self.scene.rootNode.childNode(withName: "sq-\(row)-\(col)", recursively: false) else { return }
                    guard let kind = dragonKind else {
                        self.stardust(at: tile.position)
                        tile.runAction(.sequence([
                            .group([.moveBy(x: 0, y: -2.5, z: 0, duration: 0.6), .fadeOut(duration: 0.6)]),
                            .removeFromParentNode()
                        ]))
                        return
                    }
                    self.elementBurst(at: tile.position, kind: kind)
                    if kind == .fire {
                        // The square glows like an ember, then falls away.
                        tile.geometry?.firstMaterial?.emission.contents = UIColor(red: 1.0, green: 0.35, blue: 0.05, alpha: 1)
                        tile.runAction(.sequence([
                            .wait(duration: 0.5),
                            .group([.moveBy(x: 0, y: -2.5, z: 0, duration: 0.7), .fadeOut(duration: 0.7)]),
                            .removeFromParentNode()
                        ]))
                    } else {
                        // The square freezes white, then shatters into little cubes of ice.
                        tile.geometry?.firstMaterial?.diffuse.contents = UIColor(red: 0.85, green: 0.95, blue: 1.0, alpha: 1)
                        tile.geometry?.firstMaterial?.emission.contents = UIColor(red: 0.25, green: 0.45, blue: 0.6, alpha: 1)
                        self.pixelate(row: row, col: col)
                        self.schedule(after: 0.5, token: token) { self.crumble(row: row, col: col, fraction: 1) }
                    }
                }
            }
        }

        }

        // The frame goes last, the attacker leaves, and the game is over.
        schedule(after: lastBite + 0.8, token: token) {
            for item in self.boardNodes where item.node.name == nil {
                item.node.runAction(.sequence([
                    .group([.moveBy(x: 0, y: -2.5, z: 0, duration: 0.6), .fadeOut(duration: 0.6)]),
                    .removeFromParentNode()
                ]))
            }
        }
        schedule(after: max(lastBite + 1.6, duration), token: token) {
            shark.removeFromParentNode()
            self.sharkRoot = nil
            onFinished()
        }
    }

    /// A burst of flames (fire dragon) or frost (ice dragon) where the breath lands.
    private func elementBurst(at origin: SCNVector3, kind: DragonKind) {
        let burst = SCNParticleSystem()
        burst.loops = false
        burst.emissionDuration = 0.1
        burst.birthRate = 900
        burst.particleLifeSpan = 0.9
        burst.particleLifeSpanVariation = 0.4
        burst.particleVelocity = 2.0
        burst.particleVelocityVariation = 1.2
        burst.particleSize = 0.16
        burst.particleSizeVariation = 0.08
        burst.spreadingAngle = 90
        burst.emittingDirection = SCNVector3(0, 1, 0)
        burst.isLightingEnabled = false
        burst.blendMode = .additive
        if kind == .fire {
            burst.particleColor = UIColor(red: 1.0, green: 0.45, blue: 0.08, alpha: 1)
            burst.particleColorVariation = SCNVector4(0.05, 0.25, 0.1, 0)
            burst.acceleration = SCNVector3(0, 1.5, 0)
        } else {
            burst.particleColor = UIColor(red: 0.8, green: 0.94, blue: 1.0, alpha: 1)
            burst.particleColorVariation = SCNVector4(0.05, 0.05, 0.0, 0)
            burst.acceleration = SCNVector3(0, -0.8, 0)
        }
        let emitter = SCNNode()
        emitter.position = SCNVector3(origin.x, 0.25, origin.z)
        emitter.addParticleSystem(burst)
        effectsNode.addChildNode(emitter)
        emitter.runAction(.sequence([.wait(duration: 2.0), .removeFromParentNode()]))
    }

    // MARK: Spaceship attack (Outer Space theme)

    /// The ship hovers along its route and fires short red bolts at the board. Every square is shot twice,
    /// in random order: the first hit blows up any piece and breaks the square into a 4 x 4 grid of little
    /// cubes; the second knocks half of them away; the rest fall at the very end.
    /// Returns the time (in seconds) when the last cube has gone.
    private func scheduleShipAttack(state: GameState, path: [SIMD2<Float>], headings: [Float],
                                    flyHeight: Float, token: Int) -> Double {
        let attackStart = Double(SharkRig.stalkDuration)
        let pathEnd = Double(path.count) / SharkRig.frameRate
        var squares: [Position] = []
        for row in 0..<8 {
            for col in 0..<8 { squares.append(Position(row: row, col: col)) }
        }
        let rounds: [[Position]] = [squares.shuffled(), squares.shuffled()]
        let totalShots = Double(squares.count * 2)
        let window = max(3.0, pathEnd - attackStart - 0.8)
        let interval = min(0.1, max(0.03, window / totalShots))
        let flight = 0.12

        let boltGeometry = SCNCapsule(capRadius: 0.04, height: 0.5)
        let boltMaterial = SCNMaterial()
        boltMaterial.lightingModel = .constant
        boltMaterial.diffuse.contents = UIColor(red: 1.0, green: 0.15, blue: 0.1, alpha: 1)
        boltMaterial.emission.contents = UIColor(red: 1.0, green: 0.15, blue: 0.1, alpha: 1)
        boltGeometry.materials = [boltMaterial]

        var time = attackStart + 0.5
        var lastImpact = time
        for (roundIndex, round) in rounds.enumerated() {
            for position in round {
                let fireTime = time
                let impactTime = fireTime + flight
                time += interval
                lastImpact = impactTime

                let jitterX = Float.random(in: -0.2...0.2)
                let jitterZ = Float.random(in: -0.2...0.2)
                let ground = BoardScene.worldPosition(row: position.row, col: position.col, y: 0.12)
                let target = SCNVector3(ground.x + jitterX, ground.y, ground.z + jitterZ)

                let frame = min(Int(fireTime * SharkRig.frameRate), path.count - 1)
                let heading: Float = headings[frame]
                let gunX: Float = path[frame].x + cos(heading) * SpaceshipRig.gunForward * SpaceshipRig.scale
                let gunZ: Float = path[frame].y - sin(heading) * SpaceshipRig.gunForward * SpaceshipRig.scale
                let gun = SCNVector3(gunX, flyHeight - 0.15, gunZ)

                schedule(after: fireTime, token: token) {
                    let bolt = SCNNode()
                    let body = SCNNode(geometry: boltGeometry)
                    body.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)     // lay the capsule along the flight direction
                    bolt.addChildNode(body)
                    bolt.position = gun
                    self.effectsNode.addChildNode(bolt)
                    bolt.look(at: target)
                    bolt.runAction(.sequence([.move(to: target, duration: flight), .removeFromParentNode()]))
                    Feedback.zap()
                }

                let isFirstHit = roundIndex == 0
                schedule(after: impactTime, token: token) {
                    self.redSparks(at: target)
                    if isFirstHit {
                        let dx: Float = target.x - gun.x
                        let dz: Float = target.z - gun.z
                        let length: Float = max(0.001, (dx * dx + dz * dz).squareRoot())
                        let direction = SCNVector3(dx / length, 0, dz / length)
                        if let piece = state[position],
                           let node = self.piecesNode.childNode(withName: "pc-\(position.row)-\(position.col)", recursively: false) {
                            self.shatter(node, piece: piece, direction: direction)
                            Feedback.capture(isKing: piece.isKing)
                        }
                        self.pixelate(row: position.row, col: position.col)
                    } else {
                        self.crumble(row: position.row, col: position.col, fraction: 0.5)
                    }
                }
            }
        }

        // Whatever cubes are left fall away.
        let cleanup = lastImpact + 0.3
        schedule(after: cleanup, token: token) {
            for key in Array(self.pixelTiles.keys) {
                let parts = key.split(separator: "-")
                if parts.count == 3, let row = Int(parts[1]), let col = Int(parts[2]) {
                    self.crumble(row: row, col: col, fraction: 1)
                }
            }
        }
        return cleanup + 0.4
    }

    /// Replaces a square with a 4 x 4 grid of small cubes that look the same.
    private func pixelate(row: Int, col: Int) {
        let name = "sq-\(row)-\(col)"
        guard let tile = scene.rootNode.childNode(withName: name, recursively: false) else { return }
        let origin = tile.position
        let skin = tile.geometry?.firstMaterial
        tile.removeFromParentNode()

        let cube = SCNBox(width: 0.25, height: 0.2, length: 0.25, chamferRadius: 0)
        if let skin { cube.materials = [skin] }
        var cubes: [SCNNode] = []
        for i in 0..<4 {
            for j in 0..<4 {
                let node = SCNNode(geometry: cube)
                node.position = SCNVector3(origin.x - 0.375 + Float(i) * 0.25, origin.y, origin.z - 0.375 + Float(j) * 0.25)
                node.runAction(.sequence([.moveBy(x: 0, y: 0.12, z: 0, duration: 0.05),
                                          .moveBy(x: 0, y: -0.12, z: 0, duration: 0.08)]))
                effectsNode.addChildNode(node)
                cubes.append(node)
            }
        }
        pixelTiles[name] = cubes.shuffled()
    }

    /// Knocks a share of a broken square's cubes away (1 = all of what is left).
    private func crumble(row: Int, col: Int, fraction: Double) {
        let name = "sq-\(row)-\(col)"
        guard let cubes = pixelTiles[name], !cubes.isEmpty else { return }
        let count = fraction >= 1 ? cubes.count : max(1, Int(Double(cubes.count) * fraction))
        for cube in cubes.prefix(count) {
            let dx = CGFloat.random(in: -0.6...0.6)
            let dy = CGFloat.random(in: 0.5...1.5)
            let dz = CGFloat.random(in: -0.6...0.6)
            let fly = SCNAction.group([
                .moveBy(x: dx, y: dy, z: dz, duration: 0.5),
                .fadeOut(duration: 0.5),
                .scale(to: 0.2, duration: 0.5)
            ])
            fly.timingMode = .easeOut
            cube.runAction(.sequence([.wait(duration: Double.random(in: 0...0.2)), fly, .removeFromParentNode()]))
        }
        let rest = Array(cubes.dropFirst(count))
        pixelTiles[name] = rest.isEmpty ? nil : rest
    }

    /// A quick burst of red-orange sparks.
    private func redSparks(at origin: SCNVector3) {
        let sparks = SCNParticleSystem()
        sparks.birthRate = 700
        sparks.loops = false
        sparks.emissionDuration = 0.05
        sparks.particleLifeSpan = 0.35
        sparks.particleLifeSpanVariation = 0.15
        sparks.particleVelocity = 1.8
        sparks.particleVelocityVariation = 1.0
        sparks.particleSize = 0.045
        sparks.particleSizeVariation = 0.02
        sparks.particleColor = UIColor(red: 1.0, green: 0.28, blue: 0.1, alpha: 1)
        sparks.spreadingAngle = 140
        sparks.emittingDirection = SCNVector3(0, 1, 0)
        sparks.acceleration = SCNVector3(0, -3, 0)
        sparks.blendMode = .additive
        sparks.isLightingEnabled = false
        let emitter = SCNNode()
        emitter.position = origin
        emitter.addParticleSystem(sparks)
        effectsNode.addChildNode(emitter)
        emitter.runAction(.sequence([.wait(duration: 1.0), .removeFromParentNode()]))
    }

    /// Ends the shark scene (a new game was started): the shark leaves, the board comes back, the camera resets.
    func clearShark(flipped: Bool) {
        guard sharkRoot != nil || boardNodes.contains(where: { $0.node.parent == nil }) else { return }
        animationToken += 1
        isAnimating = false
        sharkRoot?.removeAllActions()
        sharkRoot?.removeFromParentNode()
        sharkRoot = nil
        pixelTiles.removeAll()
        effectsNode.childNodes.forEach { $0.removeFromParentNode() }
        ambientNode.removeAllActions()
        ambientNode.light?.intensity = 350
        for item in boardNodes {
            item.node.removeAllActions()
            item.node.opacity = 1
            item.node.position = item.position
            // A dragon may have scorched or frozen a square: put its colour back.
            if let name = item.node.name, name.hasPrefix("sq-"), let skin = item.node.geometry?.firstMaterial {
                let parts = name.split(separator: "-")
                if parts.count == 3, let row = Int(parts[1]), let col = Int(parts[2]) {
                    skin.diffuse.contents = (row + col) % 2 == 1 ? darkSquareColor : lightSquareColor
                    skin.emission.contents = UIColor.black
                }
            }
            if item.node.parent == nil { scene.rootNode.addChildNode(item.node) }
        }
        setViewpoint(flipped: flipped)
    }

    /// A burst of drifting gold and violet sparkles.
    private func stardust(at origin: SCNVector3) {
        let emitter = SCNNode()
        emitter.position = SCNVector3(origin.x, 0.3, origin.z)
        emitter.addParticleSystem(makeStardust(birthRate: 450, lifeSpan: 1.7, velocity: 2.2, continuous: false))
        effectsNode.addChildNode(emitter)
        emitter.runAction(.sequence([.wait(duration: 2.5), .removeFromParentNode()]))
    }

    /// A cloud of dark red drifting through the water.
    private func bloodCloud(at origin: SCNVector3) {
        let emitter = SCNNode()
        emitter.position = SCNVector3(origin.x, 0.25, origin.z)
        emitter.addParticleSystem(makeBlood(birthRate: 160, lifeSpan: 2.2, velocity: 1.2, size: 0.3, continuous: false))
        effectsNode.addChildNode(emitter)
        emitter.runAction(.sequence([.wait(duration: 3.0), .removeFromParentNode()]))
    }

    private func makeBlood(birthRate: CGFloat, lifeSpan: CGFloat, velocity: CGFloat, size: CGFloat, continuous: Bool) -> SCNParticleSystem {
        let blood = SCNParticleSystem()
        blood.birthRate = birthRate
        blood.loops = continuous
        blood.emissionDuration = continuous ? 1 : 0.15
        blood.particleLifeSpan = lifeSpan
        blood.particleLifeSpanVariation = lifeSpan * 0.4
        blood.particleVelocity = velocity
        blood.particleVelocityVariation = velocity * 0.6
        blood.particleSize = size
        blood.particleSizeVariation = size * 0.5
        blood.particleColor = UIColor(red: 0.50, green: 0.0, blue: 0.03, alpha: 0.65)
        blood.spreadingAngle = 180
        blood.emittingDirection = SCNVector3(0, 1, 0)
        blood.acceleration = SCNVector3(0, 0.15, 0)
        blood.dampingFactor = 1.5
        blood.blendMode = .alpha
        blood.isLightingEnabled = false
        return blood
    }

    private func makeStardust(birthRate: CGFloat, lifeSpan: CGFloat, velocity: CGFloat, continuous: Bool) -> SCNParticleSystem {
        let dust = SCNParticleSystem()
        dust.birthRate = birthRate
        dust.loops = continuous
        dust.emissionDuration = continuous ? 1 : 0.1
        dust.particleLifeSpan = lifeSpan
        dust.particleLifeSpanVariation = lifeSpan * 0.4
        dust.particleVelocity = velocity
        dust.particleVelocityVariation = velocity * 0.6
        dust.particleSize = 0.05
        dust.particleSizeVariation = 0.035
        dust.particleColor = UIColor(red: 1.0, green: 0.85, blue: 0.45, alpha: 1)
        dust.particleColorVariation = SCNVector4(0.12, 0.3, 0.3, 0)   // varies from gold toward violet and white
        dust.spreadingAngle = 180
        dust.emittingDirection = SCNVector3(0, 1, 0)
        dust.acceleration = SCNVector3(0, 0.5, 0)
        dust.dampingFactor = 1.2
        dust.blendMode = .additive
        dust.isLightingEnabled = false
        return dust
    }

    // MARK: Destruction

    /// Blows a captured piece apart: shards with physics, a dust/spark burst, a flash, and a camera shake.
    /// `direction` is the way the capturing piece was travelling, so debris flies away from the impact.
    private func shatter(_ victim: SCNNode, piece: Piece, direction: SCNVector3) {
        let origin = victim.position
        victim.removeFromParentNode()

        let baseColor = piece.color == .red ? redPieceColor : blackPieceColor
        let shardMaterial = material(color: baseColor, roughness: 0.35, metalness: 0.3)
        let shardCount = piece.isKing ? 22 : 16

        for _ in 0..<shardCount {
            let size = CGFloat.random(in: 0.07...0.17)
            let geometry = SCNBox(width: size, height: size * 0.7, length: size * 1.2, chamferRadius: size * 0.1)
            geometry.firstMaterial = shardMaterial

            let shard = SCNNode(geometry: geometry)
            shard.position = SCNVector3(origin.x + Float.random(in: -0.25...0.25),
                                        0.1 + Float.random(in: 0...0.2),
                                        origin.z + Float.random(in: -0.25...0.25))
            shard.eulerAngles = SCNVector3(Float.random(in: 0...Float.pi),
                                           Float.random(in: 0...Float.pi),
                                           Float.random(in: 0...Float.pi))
            shard.castsShadow = true

            // Fly outward from the piece's centre, carried along the jump direction, and up.
            var outX = shard.position.x - origin.x
            var outZ = shard.position.z - origin.z
            let length = max((outX * outX + outZ * outZ).squareRoot(), 0.001)
            outX /= length
            outZ /= length
            let spread = Float.random(in: 0.8...2.2)
            let carry = Float.random(in: 1.0...2.5)

            let body = SCNPhysicsBody(type: .dynamic, shape: nil)
            body.mass = 0.1
            body.restitution = 0.3
            body.friction = 0.7
            body.velocity = SCNVector3(outX * spread + direction.x * carry,
                                       Float.random(in: 2.0...4.0),
                                       outZ * spread + direction.z * carry)
            body.angularVelocity = SCNVector4(Float.random(in: -1...1),
                                              Float.random(in: -1...1),
                                              Float.random(in: -1...1),
                                              Float.random(in: 4...14))
            shard.physicsBody = body

            effectsNode.addChildNode(shard)
            shard.runAction(.sequence([.wait(duration: 1.8), .fadeOut(duration: 0.5), .removeFromParentNode()]))
        }

        burst(at: origin)
        shakeCamera(strength: piece.isKing ? 0.12 : 0.07)
    }

    /// Dust cloud, sparks, and a brief orange flash at the point of impact.
    private func burst(at origin: SCNVector3) {
        let dust = SCNParticleSystem()
        dust.birthRate = 500
        dust.loops = false
        dust.emissionDuration = 0.08
        dust.particleLifeSpan = 0.8
        dust.particleLifeSpanVariation = 0.3
        dust.particleVelocity = 1.6
        dust.particleVelocityVariation = 1.0
        dust.particleSize = 0.06
        dust.particleSizeVariation = 0.03
        dust.particleColor = UIColor(white: 0.8, alpha: 0.7)
        dust.spreadingAngle = 180
        dust.emittingDirection = SCNVector3(0, 1, 0)
        dust.acceleration = SCNVector3(0, -1.5, 0)
        dust.blendMode = .alpha
        dust.isLightingEnabled = false

        let sparks = SCNParticleSystem()
        sparks.birthRate = 300
        sparks.loops = false
        sparks.emissionDuration = 0.05
        sparks.particleLifeSpan = 0.5
        sparks.particleLifeSpanVariation = 0.2
        sparks.particleVelocity = 3.5
        sparks.particleVelocityVariation = 2.0
        sparks.particleSize = 0.03
        sparks.particleColor = UIColor(red: 1.0, green: 0.7, blue: 0.2, alpha: 1)
        sparks.spreadingAngle = 180
        sparks.emittingDirection = SCNVector3(0, 1, 0)
        sparks.acceleration = SCNVector3(0, -6, 0)
        sparks.blendMode = .additive
        sparks.isLightingEnabled = false

        let emitter = SCNNode()
        emitter.position = SCNVector3(origin.x, 0.2, origin.z)
        emitter.addParticleSystem(dust)
        emitter.addParticleSystem(sparks)
        effectsNode.addChildNode(emitter)
        emitter.runAction(.sequence([.wait(duration: 2.0), .removeFromParentNode()]))

        flashNode.position = SCNVector3(origin.x, 0.8, origin.z)
        flashNode.runAction(.customAction(duration: 0.25) { node, elapsed in
            node.light?.intensity = 4000 * (1 - elapsed / 0.25)
        }, forKey: "flash")
    }

    private func shakeCamera(strength: Float) {
        guard let cameraNode else { return }
        let base = cameraBasePosition
        var steps: [SCNAction] = [.move(to: base, duration: 0)]
        for _ in 0..<8 {
            let offset = SCNVector3(base.x + Float.random(in: -strength...strength),
                                    base.y + Float.random(in: -strength...strength),
                                    base.z)
            steps.append(.move(to: offset, duration: 0.035))
        }
        steps.append(.move(to: base, duration: 0.05))
        cameraNode.runAction(.sequence(steps), forKey: "shake")
    }

    // MARK: Node factories

    private func makePiece(_ piece: Piece, at pos: Position) -> SCNNode {
        let color = piece.color == .red ? redPieceColor : blackPieceColor
        let root = SCNNode()
        root.name = "pc-\(pos.row)-\(pos.col)"
        root.position = BoardScene.worldPosition(row: pos.row, col: pos.col)

        let body = SCNCylinder(radius: 0.38, height: 0.22)
        body.firstMaterial = material(color: color, roughness: 0.25, metalness: 0.3)
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position = SCNVector3(0, 0.11, 0)
        bodyNode.castsShadow = true
        root.addChildNode(bodyNode)

        // Raised inner ring so pieces read as checkers rather than plain discs
        let ring = SCNTorus(ringRadius: 0.27, pipeRadius: 0.025)
        ring.firstMaterial = material(color: color.withAlphaComponent(1), roughness: 0.15, metalness: 0.6)
        let ringNode = SCNNode(geometry: ring)
        ringNode.position = SCNVector3(0, 0.225, 0)
        root.addChildNode(ringNode)

        if piece.isKing {
            let crown = SCNCylinder(radius: 0.26, height: 0.14)
            crown.firstMaterial = material(color: UIColor(red: 0.95, green: 0.78, blue: 0.25, alpha: 1),
                                           roughness: 0.2, metalness: 0.9)
            let crownNode = SCNNode(geometry: crown)
            crownNode.position = SCNVector3(0, 0.29, 0)
            crownNode.castsShadow = true
            root.addChildNode(crownNode)
        }
        return root
    }

    /// A flat glowing disc on a square. It carries the square's name so taps on it count as taps on the square.
    private func makeDisc(at pos: Position, color: UIColor, radius: CGFloat, y: CGFloat = 0.012) -> SCNNode {
        let disc = SCNCylinder(radius: radius, height: 0.01)
        let mat = SCNMaterial()
        mat.diffuse.contents = color.withAlphaComponent(0.55)
        mat.emission.contents = color
        mat.lightingModel = .constant
        mat.isDoubleSided = true
        disc.firstMaterial = mat
        let node = SCNNode(geometry: disc)
        node.name = "sq-\(pos.row)-\(pos.col)"
        node.position = BoardScene.worldPosition(row: pos.row, col: pos.col, y: y)
        return node
    }

    private func material(color: UIColor, roughness: CGFloat, metalness: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.roughness.contents = roughness
        m.metalness.contents = metalness
        return m
    }
}
