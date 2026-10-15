import SwiftUI

/// Gently falling snow in two layers: small slow flakes far away, bigger faster ones close up.
/// One Canvas redrawn every frame; the positions are maths on the clock, so there is no state.
struct SnowfallView: View {
    private struct Flake {
        let x: Double        // 0...1 across the screen
        let y: Double        // head start down the screen, 0...1
        let speed: Double    // screen heights per second
        let size: CGFloat
        let sway: Double     // how far it drifts side to side, in points
        let phase: Double
        let alpha: Double
    }

    private static func rnd(_ a: Int, _ b: Int) -> Double {
        let x = sin(Double(a * 131 + b * 977 + 13)) * 43758.5453
        return x - floor(x)
    }

    private static let flakes: [Flake] = (0..<170).map { i in
        let near = i % 3 == 0
        return Flake(x: rnd(i, 1),
                     y: rnd(i, 2),
                     speed: near ? 0.07 + 0.05 * rnd(i, 3) : 0.03 + 0.03 * rnd(i, 3),
                     size: near ? 2.6 + 2.2 * CGFloat(rnd(i, 4)) : 1.0 + 1.4 * CGFloat(rnd(i, 4)),
                     sway: 8 + 22 * rnd(i, 5),
                     phase: rnd(i, 6) * 6.28,
                     alpha: near ? 0.85 : 0.55)
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                for flake in Self.flakes {
                    var fall = (flake.y + t * flake.speed).truncatingRemainder(dividingBy: 1.1)
                    if fall < 0 { fall += 1.1 }
                    let y = (fall - 0.05) * size.height
                    let x = flake.x * size.width + sin(t * 0.8 + flake.phase) * flake.sway
                    let rect = CGRect(x: x, y: y, width: flake.size, height: flake.size)
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(flake.alpha)))
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}
