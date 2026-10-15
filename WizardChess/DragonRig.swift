import SceneKit
import UIKit

/// Which dragon: the Sunset one breathes fire, the Snowy Night one is an ice dragon that breathes frost.
enum DragonKind {
    case fire, ice
}

/// The dragon that visits the Sunset and Snowy Night themes when you lose.
///
/// Model: "Dragon Evolved" by Quaternius (CC0 / public domain). `dragon.obj` is the dragon with its wings up and
/// `dragon_down.obj` the same dragon with its wings down; the game blends between the two to flap them.
/// Both face +x and have their colours stored on their points, like the shark.
enum DragonRig {
    static let scale: Float = 1.5
    /// How high the middle of the dragon flies above the board.
    static let height: Float = 3.6
    /// Where its mouth is, in the model's own units (before `scale`), and the way the breath points (down and forward).
    static let mouth = SCNVector3(1.17, -0.05, 0)
    static let breathDirection = SCNVector3(0.62, -0.78, 0)
    /// How far ahead of the dragon (along the ground) its breath lands.
    static let groundReach: Float = 4.2
    static let flapPeriod: Double = 0.62

    struct Model {
        let root: SCNNode     // moves and turns
        let body: SCNNode     // banks (rolls) inside the root
        let mesh: SCNNode     // carries the wing-flap blend
    }

    /// Turns the brown-orange dragon into an ice dragon: dark parts become deep blue, the body icy blue, light parts white.
    private static func iceColor(_ r: Float, _ g: Float, _ b: Float) -> (Float, Float, Float) {
        let light: Float = 0.3 * r + 0.59 * g + 0.11 * b
        let t: Float = min(1, light / 0.55)
        func mix(_ a: Float, _ b: Float, _ f: Float) -> Float { a + (b - a) * f }
        if t < 0.6 {
            let f: Float = t / 0.6
            return (mix(0.05, 0.55, f), mix(0.10, 0.82, f), mix(0.22, 0.98, f))
        }
        let f: Float = (t - 0.6) / 0.4
        return (mix(0.55, 0.95, f), mix(0.82, 0.99, f), mix(0.98, 1.0, f))
    }

    static func makeModel(kind: DragonKind) -> Model {
        let root = SCNNode()
        let body = SCNNode()
        body.scale = SCNVector3(scale, scale, scale)
        let mesh = SCNNode()

        var recolor: ((Float, Float, Float) -> (Float, Float, Float))?
        if kind == .ice {
            recolor = { (r: Float, g: Float, b: Float) -> (Float, Float, Float) in DragonRig.iceColor(r, g, b) }
        }
        if let base = SharkRig.loadColoredMesh(named: "dragon", recolor: recolor) {
            print("[Attack] dragon.obj loaded")
            mesh.geometry = base
            if let down = SharkRig.loadColoredMesh(named: "dragon_down", recolor: recolor) {
                let morpher = SCNMorpher()
                morpher.calculationMode = .normalized
                morpher.targets = [down]
                mesh.morpher = morpher
            }
        } else {
            // Fallback if the model file is missing: a plain cone with two flat wings.
            print("[Attack] dragon.obj NOT found or unreadable - using a plain stand-in")
            let color = kind == .ice ? UIColor(red: 0.6, green: 0.85, blue: 1, alpha: 1)
                                     : UIColor(red: 0.8, green: 0.25, blue: 0.1, alpha: 1)
            let cone = SCNCone(topRadius: 0.1, bottomRadius: 0.45, height: 2.2)
            cone.firstMaterial?.diffuse.contents = color
            let coneNode = SCNNode(geometry: cone)
            coneNode.eulerAngles = SCNVector3(0, 0, -Float.pi / 2)
            mesh.addChildNode(coneNode)
            let wing = SCNBox(width: 0.6, height: 0.04, length: 4, chamferRadius: 0)
            wing.firstMaterial?.diffuse.contents = color
            mesh.addChildNode(SCNNode(geometry: wing))
        }
        body.addChildNode(mesh)
        root.addChildNode(body)
        return Model(root: root, body: body, mesh: mesh)
    }

    /// A continuous jet of flames or frost from the mouth. Attach to `root` (not the scaled body).
    static func makeBreath(kind: DragonKind) -> SCNNode {
        let jet = SCNParticleSystem()
        jet.loops = true
        jet.birthRate = 700
        jet.particleLifeSpan = 0.9
        jet.particleLifeSpanVariation = 0.25
        jet.particleVelocity = 5.5
        jet.particleVelocityVariation = 1.2
        jet.spreadingAngle = 14
        jet.emittingDirection = breathDirection
        jet.particleSize = kind == .fire ? 0.30 : 0.22
        jet.particleSizeVariation = 0.12
        jet.isLightingEnabled = false
        jet.blendMode = .additive
        if kind == .fire {
            jet.particleColor = UIColor(red: 1.0, green: 0.5, blue: 0.12, alpha: 1)
            jet.particleColorVariation = SCNVector4(0.05, 0.25, 0.1, 0)
            jet.acceleration = SCNVector3(0, 0.8, 0)
        } else {
            jet.particleColor = UIColor(red: 0.75, green: 0.92, blue: 1.0, alpha: 1)
            jet.particleColorVariation = SCNVector4(0.05, 0.05, 0.0, 0)
            jet.acceleration = SCNVector3(0, -0.4, 0)
        }
        let node = SCNNode()
        node.position = SCNVector3(mouth.x * scale, mouth.y * scale, mouth.z * scale)
        node.addParticleSystem(jet)
        return node
    }
}
