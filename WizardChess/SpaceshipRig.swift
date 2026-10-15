import SceneKit
import UIKit

/// The spaceship that visits the Outer Space theme when you lose. It flies the same route the shark does,
/// but hovers above the board and shoots short red bolts at it.
///
/// Model: "Spaceship" by Quaternius (CC0 / public domain). `ship.obj` is 3.6 units long and faces +x;
/// colours are stored on its points, like the shark's.
enum SpaceshipRig {
    static let height: Float = 1.7
    static let scale: Float = 1.3
    static let reach: Float = 0.0
    /// Where the bolts leave the ship, ahead of its centre.
    static let gunForward: Float = 1.3

    struct Model {
        let root: SCNNode     // moves and turns
        let body: SCNNode     // banks (rolls) inside the root
    }

    static func makeModel() -> Model {
        let root = SCNNode()
        let body = SCNNode()
        body.scale = SCNVector3(scale, scale, scale)

        if let geometry = SharkRig.loadColoredMesh(named: "ship") {
            print("[Attack] ship.obj loaded")
            geometry.firstMaterial?.specular.contents = UIColor(white: 0.8, alpha: 1)
            geometry.firstMaterial?.shininess = 0.8
            body.addChildNode(SCNNode(geometry: geometry))
        } else {
            // Fallback if the model file is missing: a simple flying saucer.
            print("[Attack] ship.obj NOT found or unreadable - using the plain saucer")
            let saucer = SCNCylinder(radius: 1.4, height: 0.25)
            saucer.firstMaterial?.diffuse.contents = UIColor(white: 0.75, alpha: 1)
            saucer.firstMaterial?.lightingModel = .blinn
            body.addChildNode(SCNNode(geometry: saucer))
            let dome = SCNSphere(radius: 0.5)
            dome.firstMaterial?.diffuse.contents = UIColor(red: 0.3, green: 0.8, blue: 1, alpha: 1)
            let domeNode = SCNNode(geometry: dome)
            domeNode.position = SCNVector3(0, 0.2, 0)
            body.addChildNode(domeNode)
        }
        root.addChildNode(body)

        // Engine glow at the back.
        let glow = SCNSphere(radius: 0.22)
        glow.firstMaterial?.diffuse.contents = UIColor.black
        glow.firstMaterial?.emission.contents = UIColor(red: 0.4, green: 0.9, blue: 1, alpha: 1)
        let glowNode = SCNNode(geometry: glow)
        glowNode.position = SCNVector3(-1.7 * scale, 0.1, 0)
        body.addChildNode(glowNode)

        return Model(root: root, body: body)
    }
}
