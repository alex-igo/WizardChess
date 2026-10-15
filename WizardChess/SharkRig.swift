import SceneKit
import UIKit

/// Everything about the Ocean shark that doesn't depend on the board: its 3D model and the path it swims.
/// (`BoardScene` uses these to run the attack and to decide when each piece gets eaten.)
enum SharkRig {
    static let frameRate = 60.0
    /// How long the shark circles the board before it attacks.
    static let stalkDuration = 5.0
    /// The shark swims at this height above the board.
    static let height: Float = 0.55
    /// The model is built about 6 units long, then scaled up by this much.
    static let scale: Float = 1.25
    /// How far in front of the shark's middle its nose is.
    static let noseOffset: Float = 3.0 * scale
    /// How close (in squares) the nose must get to chew up a piece or square.
    static let biteRadius: Float = 1.6


    // MARK: Path

    /// Where the shark is (x, z on the board) for every 1/60 s of the whole scene.
    /// First it circles the board, speeding up; then it makes three sweeps across it.
    static func makePath() -> [SIMD2<Float>] {
        var points: [SIMD2<Float>] = []

        // 1. Stalking: part of a lap round the board at a radius of 7.5, starting slow and speeding up.
        let radius: Float = 7.5
        let stalkFrames = Int(stalkDuration * frameRate)
        let sweep = 2 * Float.pi * 0.6
        for k in 0...stalkFrames {
            let u = Float(k) / Float(stalkFrames)
            let eased: Float = pow(u, 1.5)
            let angle: Float = Float.pi - sweep * (1 - eased)
            points.append(SIMD2(radius * cos(angle), radius * sin(angle)))
        }

        // 2. The attack: a smooth curve through waypoints. Every game is different: the sweeps come in a
        //    random order (3 to 4 of them), the turns at the ends swing out by different amounts, and the
        //    speed varies. The three main lines are about 3 squares apart so the open mouth reaches every square.
        let baseLanes: [Float] = [-3, 0, 3].shuffled()
        var lanes: [Float] = baseLanes.map { (lane: Float) -> Float in lane + Float.random(in: -0.1...0.1) }
        if Bool.random() { lanes.append(Float.random(in: -2.5...2.5)) }   // sometimes a bonus pass
        let attackSpeed = Float.random(in: 8...11)                         // units per second

        var waypoints: [SIMD2<Float>] = [SIMD2<Float>(-7.5, 0)]
        var side: Float = -1                       // which end it is on: -1 = left, +1 = right
        let first: Float = lanes[0]
        let firstBulge: Float = Float.random(in: 8.2...9.2)
        waypoints.append(SIMD2<Float>(side * firstBulge, first * 0.5))
        waypoints.append(SIMD2<Float>(side * 7.2, first))
        for index in 0..<lanes.count {
            let z: Float = lanes[index]
            let exitX: Float = Float.random(in: 8.6...9.8)
            // Straight across the board, then out past the far edge.
            waypoints.append(SIMD2<Float>(side * 4, z))
            waypoints.append(SIMD2<Float>(-side * 4, z))
            waypoints.append(SIMD2<Float>(-side * exitX, z))
            if index + 1 < lanes.count {
                // Swing round the end and line up with the next pass.
                let next: Float = lanes[index + 1]
                let swing: Float = Float.random(in: 10...11.6)
                let jitter: Float = Float.random(in: -0.5...0.5)
                let midZ: Float = (z + next) / 2 + jitter
                let lineUpX: Float = Float.random(in: 8.6...9.4)
                waypoints.append(SIMD2<Float>(-side * swing, midZ))
                waypoints.append(SIMD2<Float>(-side * lineUpX, next))
                side = -side
            }
        }
        let curve = catmullRom(through: waypoints, samplesPerSegment: 24)

        // Walk along the curve at a steady speed, one step per frame.
        var cumulative: [Float] = [0]
        for i in 1..<curve.count {
            cumulative.append(cumulative[i - 1] + simd_length(curve[i] - curve[i - 1]))
        }
        let total = cumulative[cumulative.count - 1]
        let step = attackSpeed / Float(frameRate)
        var distance: Float = step
        var segment = 0
        while distance <= total {
            while segment < curve.count - 2, cumulative[segment + 1] < distance { segment += 1 }
            let length = cumulative[segment + 1] - cumulative[segment]
            let f = length > 0 ? (distance - cumulative[segment]) / length : 0
            points.append(curve[segment] + (curve[segment + 1] - curve[segment]) * f)
            distance += step
        }
        return points
    }

    /// Frames before this one are the stalking; the attack starts here.
    static var attackStartFrame: Int { Int(stalkDuration * frameRate) }

    /// A smooth curve through `points` (a Catmull-Rom spline).
    private static func catmullRom(through points: [SIMD2<Float>], samplesPerSegment: Int) -> [SIMD2<Float>] {
        let p = [points[0]] + points + [points[points.count - 1]]
        var result: [SIMD2<Float>] = []
        for i in 0..<(p.count - 3) {
            let p0 = p[i], p1 = p[i + 1], p2 = p[i + 2], p3 = p[i + 3]
            for s in 0..<samplesPerSegment {
                let t = Float(s) / Float(samplesPerSegment)
                let t2 = t * t, t3 = t2 * t
                let x = spline(p0.x, p1.x, p2.x, p3.x, t)
                let y = spline(p0.y, p1.y, p2.y, p3.y, t)
                result.append(SIMD2<Float>(x, y))
            }
        }
        result.append(points[points.count - 1])
        return result
    }

    /// One coordinate of a Catmull-Rom curve between `p1` and `p2`, at position `t` (0 to 1).
    private static func spline(_ p0: Float, _ p1: Float, _ p2: Float, _ p3: Float, _ t: Float) -> Float {
        let t2: Float = t * t
        let t3: Float = t2 * t
        let a: Float = 2 * p1
        let b: Float = (p2 - p0) * t
        let cPart: Float = 2 * p0 - 5 * p1 + 4 * p2 - p3
        let dPart: Float = 3 * p1 - p0 - 3 * p2 + p3
        let c: Float = cPart * t2
        let d: Float = dPart * t3
        return 0.5 * (a + b + c + d)
    }

    /// The direction the shark faces at every frame, as an angle for `eulerAngles.y`.
    /// Looks a few frames ahead and behind so turns are smooth.
    static func headings(for path: [SIMD2<Float>]) -> [Float] {
        let window = 6
        return path.indices.map { i in
            let from = path[max(i - window, 0)]
            let to = path[min(i + window, path.count - 1)]
            let d = to - from
            return atan2(-d.y, d.x)
        }
    }

    // MARK: Model

    /// The real 3D shark: "Shark" by Quaternius (CC0 public domain). It lives in two files next to the
    /// code (shark.obj and shark_jaw.obj). If they are missing, the game falls back
    /// to the shark built from code further down.
    ///
    /// The model was prepared so it is 6 units long, faces +x and has its lower jaw as a separate piece
    /// that hinges at this point.
    private static let jawHinge = SCNVector3(1.6805, -0.0078, 0)

    /// Makes the body bend like a swimming fish: the further back along the body, the more it sways.
    private static let swimShader = """
    float behind = clamp((1.0 - _geometry.position.x) / 4.0, 0.0, 1.0);
    float sway = sin(scn_frame.time * 5.0 + _geometry.position.x * 1.1) * 0.35 * behind * behind;
    _geometry.position.z += sway;
    """

    /// Reads one of the shark's mesh files. They are plain text: "v x y z r g b" lines (a point and its
    /// colour), "vn" lines (surface directions) and "f" lines (triangles). Colours are stored on the points
    /// themselves, so no texture file is needed.
    static func loadColoredMesh(named name: String,
                                recolor: ((Float, Float, Float) -> (Float, Float, Float))? = nil) -> SCNGeometry? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "obj"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }

        var positions: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var colors: [Float] = []
        var indices: [Int32] = []

        text.enumerateLines { line, _ in
            if line.hasPrefix("v ") {
                let n = line.split(separator: " ").dropFirst().compactMap { Float($0) }
                if n.count >= 6 {
                    positions.append(SCNVector3(n[0], n[1], n[2]))
                    let tint: (Float, Float, Float) = recolor?(n[3], n[4], n[5]) ?? (n[3], n[4], n[5])
                    colors.append(contentsOf: [tint.0, tint.1, tint.2, 1])
                }
            } else if line.hasPrefix("vn ") {
                let n = line.split(separator: " ").dropFirst().compactMap { Float($0) }
                if n.count >= 3 { normals.append(SCNVector3(n[0], n[1], n[2])) }
            } else if line.hasPrefix("f ") {
                for token in line.split(separator: " ").dropFirst() {
                    if let first = token.split(separator: "/").first, let index = Int32(first) {
                        indices.append(index - 1)
                    }
                }
            }
        }
        guard !positions.isEmpty, positions.count == normals.count, !indices.isEmpty else { return nil }

        let colorData = colors.withUnsafeBufferPointer { Data(buffer: $0) }
        let colorSource = SCNGeometrySource(data: colorData,
                                            semantic: .color,
                                            vectorCount: positions.count,
                                            usesFloatComponents: true,
                                            componentsPerVector: 4,
                                            bytesPerComponent: MemoryLayout<Float>.size,
                                            dataOffset: 0,
                                            dataStride: MemoryLayout<Float>.size * 4)
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: positions),
                                             SCNGeometrySource(normals: normals),
                                             colorSource],
                                   elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        let skin = SCNMaterial()
        skin.lightingModel = .blinn
        skin.diffuse.contents = UIColor.white         // the colours stored on the points do the colouring
        skin.specular.contents = UIColor(white: 0.45, alpha: 1)
        skin.shininess = 0.5
        skin.isDoubleSided = true
        geometry.materials = [skin]
        return geometry
    }

    private static func loadBundledModel() -> (root: SCNNode, jaw: SCNNode, tail: SCNNode)? {
        guard let bodyGeometry = loadColoredMesh(named: "shark") else { return nil }

        let root = SCNNode()
        root.scale = SCNVector3(scale, scale, scale)

        // The body also gets the swimming bend; the jaw stays rigid so it can hinge.
        bodyGeometry.firstMaterial?.shaderModifiers = [.geometry: swimShader]
        root.addChildNode(SCNNode(geometry: bodyGeometry))

        let jaw = SCNNode()
        jaw.position = jawHinge
        if let jawGeometry = loadColoredMesh(named: "shark_jaw") {
            jaw.addChildNode(SCNNode(geometry: jawGeometry))
        }
        root.addChildNode(jaw)

        // The tail bends through the shader, so there is no separate tail piece to swing.
        return (root, jaw, SCNNode())
    }

    /// How the body fills out along its length, from 0 at the nose to 1 at its fattest.
    /// x runs from -3 (tail end) to +3 (nose).
    private static func girth(at x: Float) -> Float {
        let u = min(max((x + 3) / 6, 0), 1)
        if u < 0.38 {
            let k: Float = u / 0.38
            let smooth: Float = k * k * (3 - 2 * k)
            return 0.14 + 0.86 * smooth
        }
        let k: Float = (u - 0.38) / 0.62
        let inner: Float = max(0, 1 - pow(k, 1.8))
        return pow(inner, 0.7)          // a rounded snout
    }

    static func halfHeight(at x: Float) -> Float { 0.62 * girth(at: x) }
    static func halfWidth(at x: Float) -> Float { 0.55 * girth(at: x) }

    private static func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    private static func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
        a + (b - a) * t
    }

    /// The torpedo-shaped body, built ring by ring. Grey on top, pale underneath, and a raw red mouth.
    private static func makeBodyGeometry() -> SCNGeometry {
        let stations = 60
        let ring = 28
        let grey = SIMD3<Float>(0.27, 0.34, 0.41)
        let pale = SIMD3<Float>(0.86, 0.88, 0.88)
        let gums = SIMD3<Float>(0.40, 0.03, 0.05)

        var grid: [[SIMD3<Float>]] = []
        for i in 0...stations {
            let x: Float = -3 + 6 * Float(i) / Float(stations)
            let h = halfHeight(at: x)
            let w = halfWidth(at: x)
            var row: [SIMD3<Float>] = []
            for j in 0..<ring {
                let angle: Float = 2 * Float.pi * Float(j) / Float(ring)
                let s = sin(angle)
                let y: Float = (s >= 0 ? h : h * 0.82) * s
                row.append(SIMD3<Float>(x, y, w * cos(angle)))
            }
            grid.append(row)
        }

        var positions: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var colors: [Float] = []
        for i in 0...stations {
            for j in 0..<ring {
                let p = grid[i][j]
                let along = grid[min(i + 1, stations)][j] - grid[max(i - 1, 0)][j]
                let around = grid[i][(j + 1) % ring] - grid[i][(j + ring - 1) % ring]
                var n = simd_cross(along, around)
                let radial = SIMD3<Float>(0, p.y, p.z)
                if simd_length(n) < 1e-6 {
                    n = simd_length(radial) > 1e-6 ? radial : SIMD3<Float>(p.x > 0 ? 1 : -1, 0, 0)
                }
                n = simd_normalize(n)
                if simd_dot(n, radial) < 0 { n = -n }

                positions.append(SCNVector3(p.x, p.y, p.z))
                normals.append(SCNVector3(n.x, n.y, n.z))

                let angle: Float = 2 * Float.pi * Float(j) / Float(ring)
                let s = sin(angle)
                var color = mix(pale, grey, smoothstep(-0.3, 0.18, s))
                if p.x > 1.2 {
                    color = mix(color, gums, smoothstep(-0.55, -0.8, s))
                }
                colors.append(contentsOf: [color.x, color.y, color.z, 1])
            }
        }

        var indices: [Int32] = []
        for i in 0..<stations {
            for j in 0..<ring {
                let a = Int32(i * ring + j)
                let b = Int32(i * ring + (j + 1) % ring)
                let c = Int32((i + 1) * ring + j)
                let d = Int32((i + 1) * ring + (j + 1) % ring)
                indices.append(contentsOf: [a, c, b, b, c, d])
            }
        }

        let colorData = colors.withUnsafeBufferPointer { Data(buffer: $0) }
        let colorSource = SCNGeometrySource(data: colorData,
                                            semantic: .color,
                                            vectorCount: positions.count,
                                            usesFloatComponents: true,
                                            componentsPerVector: 4,
                                            bytesPerComponent: MemoryLayout<Float>.size,
                                            dataOffset: 0,
                                            dataStride: MemoryLayout<Float>.size * 4)
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: positions),
                                             SCNGeometrySource(normals: normals),
                                             colorSource],
                                   elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        let skin = SCNMaterial()
        skin.lightingModel = .blinn
        skin.diffuse.contents = UIColor.white          // the vertex colours above do the colouring
        skin.specular.contents = UIColor(white: 0.35, alpha: 1)
        skin.shininess = 0.3
        skin.isDoubleSided = true
        geometry.materials = [skin]
        return geometry
    }

    /// A great white built to look like something you do not want to meet: black dead eyes, old scars,
    /// raw red gums and two rows of jagged teeth. It faces +x. `jaw` hinges open and shut and
    /// `tail` swings from side to side.
    static func makeModel() -> (root: SCNNode, jaw: SCNNode, tail: SCNNode) {
        if let real = loadBundledModel() { return real }
        let root = SCNNode()
        root.scale = SCNVector3(scale, scale, scale)

        func paint(_ color: UIColor, roughness: CGFloat = 0.5) -> SCNMaterial {
            let m = SCNMaterial()
            m.lightingModel = .physicallyBased
            m.diffuse.contents = color
            m.roughness.contents = roughness
            m.metalness.contents = 0.0
            return m
        }
        let grey = UIColor(red: 0.27, green: 0.34, blue: 0.41, alpha: 1)
        let darkGrey = UIColor(red: 0.18, green: 0.23, blue: 0.29, alpha: 1)
        let pale = UIColor(red: 0.86, green: 0.88, blue: 0.88, alpha: 1)
        let bone = UIColor(red: 0.93, green: 0.90, blue: 0.78, alpha: 1)
        let scarColor = UIColor(red: 0.80, green: 0.66, blue: 0.64, alpha: 1)

        func cone(_ color: UIColor, bottomRadius: CGFloat, height: CGFloat) -> SCNNode {
            let c = SCNCone(topRadius: 0, bottomRadius: bottomRadius, height: height)
            c.firstMaterial = paint(color)
            return SCNNode(geometry: c)
        }

        root.addChildNode(SCNNode(geometry: makeBodyGeometry()))

        // Dorsal fin, with a torn notch taken out of it
        let dorsal = cone(darkGrey, bottomRadius: 0.5, height: 1.2)
        dorsal.scale = SCNVector3(1, 1, 0.16)
        dorsal.position = SCNVector3(0.2, 0.95, 0)
        dorsal.eulerAngles = SCNVector3(0, 0, 0.35)
        root.addChildNode(dorsal)

        // Side fins
        for side in [Float(1), Float(-1)] {
            let fin = cone(darkGrey, bottomRadius: 0.3, height: 1.0)
            fin.scale = SCNVector3(1, 1, 0.14)
            fin.position = SCNVector3(0.9, -0.4, 0.5 * side)
            fin.eulerAngles = SCNVector3(1.15 * side, 0, 0.55)
            root.addChildNode(fin)
        }

        // Tail, hinged where it meets the body
        let tail = SCNNode()
        tail.position = SCNVector3(-2.7, 0, 0)
        let upper = cone(grey, bottomRadius: 0.38, height: 1.7)
        upper.scale = SCNVector3(1, 1, 0.13)
        upper.position = SCNVector3(-0.55, 0.5, 0)
        upper.eulerAngles = SCNVector3(0, 0, 0.9)
        tail.addChildNode(upper)
        let lower = cone(grey, bottomRadius: 0.3, height: 1.1)
        lower.scale = SCNVector3(1, 1, 0.13)
        lower.position = SCNVector3(-0.4, -0.32, 0)
        lower.eulerAngles = SCNVector3(0, 0, 2.4)
        tail.addChildNode(lower)
        root.addChildNode(tail)

        // Eyes: glossy black, no pupil, no life
        for side in [Float(1), Float(-1)] {
            let x: Float = 2.05
            let eye = SCNSphere(radius: 0.085)
            eye.firstMaterial = paint(.black, roughness: 0.05)
            let node = SCNNode(geometry: eye)
            node.position = SCNVector3(x, 0.08, (halfWidth(at: x) - 0.01) * side)
            root.addChildNode(node)
        }

        // Old scars across the flank, and gill slits
        for (i, x) in [Float(0.2), Float(0.55), Float(0.9)].enumerated() {
            for side in [Float(1), Float(-1)] {
                let scar = SCNBox(width: 0.55, height: 0.02, length: 0.02, chamferRadius: 0)
                scar.firstMaterial = paint(scarColor, roughness: 0.8)
                let node = SCNNode(geometry: scar)
                node.position = SCNVector3(x, 0.05 + 0.04 * Float(i), halfWidth(at: x) * 0.97 * side)
                node.eulerAngles = SCNVector3(0, 0, 0.5 - 0.35 * Float(i))
                root.addChildNode(node)
            }
        }
        for i in 0..<5 {
            let x: Float = 1.15 + 0.1 * Float(i)
            for side in [Float(1), Float(-1)] {
                let slit = SCNBox(width: 0.02, height: 0.3, length: 0.02, chamferRadius: 0)
                slit.firstMaterial = paint(UIColor(red: 0.08, green: 0.1, blue: 0.13, alpha: 1), roughness: 1)
                let node = SCNNode(geometry: slit)
                node.position = SCNVector3(x, 0.02, halfWidth(at: x) * 0.96 * side)
                node.eulerAngles = SCNVector3(0, 0, 0.25)
                root.addChildNode(node)
            }
        }

        // Upper teeth: a row of jagged cones down each side of the upper jaw
        for i in 0..<9 {
            let x: Float = 1.45 + 0.17 * Float(i)
            let toothHeight: CGFloat = i % 2 == 0 ? 0.3 : 0.22
            for side in [Float(1), Float(-1)] {
                let tooth = cone(bone, bottomRadius: 0.05, height: toothHeight)
                tooth.eulerAngles = SCNVector3(Float.pi, 0, 0.12 * side)    // points down, leaning inward
                let y: Float = -0.8 * halfHeight(at: x) * 0.84
                let z: Float = halfWidth(at: x) * 0.55 * side
                tooth.position = SCNVector3(x, y - Float(toothHeight) / 2 + 0.03, z)
                root.addChildNode(tooth)
            }
        }

        // Lower jaw: a long pale wedge hinged at the back of the mouth, with its own teeth
        let hingeX: Float = 1.3
        let jaw = SCNNode()
        jaw.position = SCNVector3(hingeX, -0.85 * halfHeight(at: hingeX), 0)
        let jawLength: CGFloat = 1.65
        let wedge = cone(pale, bottomRadius: 0.38, height: jawLength)
        wedge.scale = SCNVector3(0.4, 1, 1)                        // squashed flat
        wedge.eulerAngles = SCNVector3(0, 0, -Float.pi / 2)        // lying along +x, tip forward
        wedge.position = SCNVector3(Float(jawLength) / 2, 0, 0)
        jaw.addChildNode(wedge)
        for i in 0..<8 {
            let d: Float = 0.25 + 0.18 * Float(i)                  // distance along the jaw
            let narrowing: Float = 1 - d / Float(jawLength)
            for side in [Float(1), Float(-1)] {
                let tooth = cone(bone, bottomRadius: 0.045, height: i % 2 == 0 ? 0.26 : 0.2)
                tooth.eulerAngles = SCNVector3(0, 0, -0.12)         // points up, leaning back
                tooth.position = SCNVector3(d, 0.08 + 0.1 * narrowing, 0.34 * narrowing * side)
                jaw.addChildNode(tooth)
            }
        }
        root.addChildNode(jaw)

        return (root, jaw, tail)
    }
}
