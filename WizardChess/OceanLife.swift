import SwiftUI

/// A swimmer's-eye view of the sea: sunlight shafts, drifting plankton, schools of fish at
/// several depths, swaying kelp and a rocky sea floor. Drawn with one SwiftUI Canvas that
/// redraws every frame; everything is maths on the clock, so there is no state or timers.
struct OceanLifeView: View {
    private struct Fish {
        let depth: Double      // 0 = far away and hazy ... 1 = right in front of you
        let baseY: Double      // 0...1 down the screen (shared by a whole school)
        let dx: Double         // this fish's spot inside its school
        let dy: Double
        let speed: Double      // points per second
        let size: CGFloat
        let offset: Double     // head start along the path (shared by a school)
        let movesRight: Bool
        let hue: Double
        let bobAmount: Double
        let bobSpeed: Double
        let phase: Double      // tail-beat timing, different for every fish
    }

    /// Repeatable pseudo-random number in 0..<1.
    private static func rnd(_ a: Int, _ b: Int) -> Double {
        let x = sin(Double(a * 131 + b * 977 + 7)) * 43758.5453
        return x - floor(x)
    }

    private static func makeFish() -> [Fish] {
        var result: [Fish] = []
        // (schools, fish per school, depth, size range, speed range)
        let layers: [(Int, Int, Double, ClosedRange<Double>, ClosedRange<Double>)] = [
            (4, 9, 0.15, 5...8, 10...22),    // distant schools: small, slow, bluish
            (3, 4, 0.5, 11...15, 22...40),   // middle distance
            (3, 1, 1.0, 24...34, 40...70)    // close to you: big and detailed
        ]
        var seed = 0
        for (schools, count, depth, sizes, speeds) in layers {
            for _ in 0..<schools {
                seed += 1
                let baseY = 0.1 + 0.62 * rnd(seed, 1)
                let speed = speeds.lowerBound + (speeds.upperBound - speeds.lowerBound) * rnd(seed, 2)
                let offset = rnd(seed, 3)
                let right = rnd(seed, 4) > 0.5
                let hue = [0.56, 0.08, 0.13, 0.02, 0.58, 0.11][seed % 6]
                for member in 0..<count {
                    let m = seed * 50 + member
                    result.append(Fish(
                        depth: depth,
                        baseY: baseY,
                        dx: count == 1 ? 0 : (rnd(m, 5) - 0.5) * 90,
                        dy: count == 1 ? 0 : (rnd(m, 6) - 0.5) * 0.06,
                        speed: speed,
                        size: CGFloat(sizes.lowerBound + (sizes.upperBound - sizes.lowerBound) * rnd(m, 7)),
                        offset: offset,
                        movesRight: right,
                        hue: hue,
                        bobAmount: 4 + 10 * rnd(m, 8),
                        bobSpeed: 0.5 + 1.0 * rnd(m, 9),
                        phase: rnd(m, 10) * 6.28))
                }
            }
        }
        return result
    }

    private let fish = OceanLifeView.makeFish()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                drawWater(&context, size: size, t: t)
                drawLightShafts(&context, size: size, t: t)
                for f in fish where f.depth < 0.3 { draw(f, in: &context, size: size, t: t) }
                drawPlankton(&context, size: size, t: t)
                drawKelp(&context, size: size, t: t, near: false)
                for f in fish where f.depth >= 0.3 && f.depth < 0.8 { draw(f, in: &context, size: size, t: t) }
                drawSeaFloor(&context, size: size)
                drawKelp(&context, size: size, t: t, near: true)
                for f in fish where f.depth >= 0.8 { draw(f, in: &context, size: size, t: t) }
                drawVignette(&context, size: size)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: Water and light

    private func drawWater(_ context: inout GraphicsContext, size: CGSize, t: Double) {
        let rect = CGRect(origin: .zero, size: size)
        context.fill(Path(rect), with: .linearGradient(
            Gradient(colors: [Color(red: 0.12, green: 0.60, blue: 0.74),
                              Color(red: 0.04, green: 0.32, blue: 0.50),
                              Color(red: 0.01, green: 0.12, blue: 0.26),
                              Color(red: 0.00, green: 0.05, blue: 0.13)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
    }

    private func drawLightShafts(_ context: inout GraphicsContext, size: CGSize, t: Double) {
        context.drawLayer { layer in
            layer.blendMode = .plusLighter
            for i in 0..<7 {
                let fraction = (Double(i) + 0.5) / 7
                let sway = sin(t * 0.18 + Double(i) * 1.7) * 40
                let x = fraction * Double(size.width) + sway
                let width = 26 + 44 * OceanLifeView.rnd(i, 21)
                let slant = Double(size.height) * 0.28
                let strength = 0.07 + 0.07 * (0.5 + 0.5 * sin(t * 0.4 + Double(i) * 2.1))
                var shaft = Path()
                shaft.move(to: CGPoint(x: x - width * 0.3, y: 0))
                shaft.addLine(to: CGPoint(x: x + width * 0.3, y: 0))
                shaft.addLine(to: CGPoint(x: x + slant + width * 1.6, y: Double(size.height) * 0.9))
                shaft.addLine(to: CGPoint(x: x + slant - width * 1.6, y: Double(size.height) * 0.9))
                shaft.closeSubpath()
                layer.fill(shaft, with: .linearGradient(
                    Gradient(colors: [Color.white.opacity(strength * 2), Color.white.opacity(0)]),
                    startPoint: CGPoint(x: x, y: 0),
                    endPoint: CGPoint(x: x + slant, y: Double(size.height) * 0.9)))
            }
        }
    }

    private func drawVignette(_ context: inout GraphicsContext, size: CGSize) {
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
            Gradient(colors: [Color.clear, Color.black.opacity(0.5)]),
            center: centre,
            startRadius: min(size.width, size.height) * 0.45,
            endRadius: max(size.width, size.height) * 0.8))
    }

    // MARK: Plankton ("marine snow")

    private func drawPlankton(_ context: inout GraphicsContext, size: CGSize, t: Double) {
        for i in 0..<70 {
            let depth = OceanLifeView.rnd(i, 31)                       // nearer specks drift faster and look bigger
            let w = Double(size.width), h = Double(size.height)
            let x = (OceanLifeView.rnd(i, 32) * w - t * (4 + 10 * depth) + sin(t * 0.5 + Double(i)) * 6)
                .truncatingRemainder(dividingBy: w)
            let y = (OceanLifeView.rnd(i, 33) * h + t * (3 + 6 * depth)).truncatingRemainder(dividingBy: h)
            let r = 0.6 + 1.8 * depth
            let px = x < 0 ? x + w : x
            context.fill(Path(ellipseIn: CGRect(x: px - r, y: y - r, width: r * 2, height: r * 2)),
                         with: .color(.white.opacity(0.15 + 0.35 * depth)))
        }
    }

    // MARK: Sea floor and kelp

    private func drawSeaFloor(_ context: inout GraphicsContext, size: CGSize) {
        let w = Double(size.width), h = Double(size.height)
        var floor = Path()
        floor.move(to: CGPoint(x: 0, y: h))
        var x = 0.0
        while x <= w + 10 {
            floor.addLine(to: CGPoint(x: x, y: h - 28 - 14 * sin(x * 0.02) - 8 * sin(x * 0.07 + 1)))
            x += 10
        }
        floor.addLine(to: CGPoint(x: w, y: h))
        floor.closeSubpath()
        context.fill(floor, with: .linearGradient(
            Gradient(colors: [Color(red: 0.36, green: 0.34, blue: 0.27), Color(red: 0.12, green: 0.12, blue: 0.11)]),
            startPoint: CGPoint(x: 0, y: h - 50), endPoint: CGPoint(x: 0, y: h)))

        // A few rocks resting on the sand
        for i in 0..<6 {
            let rx = (Double(i) + 0.3 + 0.4 * OceanLifeView.rnd(i, 41)) / 6 * w
            let rw = 34 + 40 * OceanLifeView.rnd(i, 42)
            let rh = rw * (0.35 + 0.25 * OceanLifeView.rnd(i, 43))
            let ry = h - 22 - 12 * sin(rx * 0.02)
            let rock = Path(ellipseIn: CGRect(x: rx - rw / 2, y: ry - rh / 2, width: rw, height: rh))
            context.fill(rock, with: .linearGradient(
                Gradient(colors: [Color(red: 0.34, green: 0.36, blue: 0.36), Color(red: 0.09, green: 0.10, blue: 0.11)]),
                startPoint: CGPoint(x: rx, y: ry - rh / 2), endPoint: CGPoint(x: rx, y: ry + rh / 2)))
        }
    }

    private func drawKelp(_ context: inout GraphicsContext, size: CGSize, t: Double, near: Bool) {
        let w = Double(size.width), h = Double(size.height)
        let count = near ? 8 : 10
        for i in 0..<count {
            let seed = near ? i + 100 : i
            let x0 = (Double(i) + 0.5 * OceanLifeView.rnd(seed, 51)) / Double(count) * w
            let height = h * (near ? 0.18 + 0.2 * OceanLifeView.rnd(seed, 52) : 0.14 + 0.16 * OceanLifeView.rnd(seed, 52))
            let phase = OceanLifeView.rnd(seed, 53) * 6.28
            var strand = Path()
            let steps = 9
            for s in 0...steps {
                let f = Double(s) / Double(steps)
                let point = CGPoint(x: x0 + sin(t * 0.9 + phase + f * 3) * f * (near ? 22 : 14),
                                    y: h - 24 - height * f)
                if s == 0 { strand.move(to: point) } else { strand.addLine(to: point) }
            }
            let color = near ? Color(red: 0.12, green: 0.32, blue: 0.16).opacity(0.85)
                             : Color(red: 0.08, green: 0.30, blue: 0.30).opacity(0.5)
            context.stroke(strand, with: .color(color),
                           style: StrokeStyle(lineWidth: near ? 7 : 4, lineCap: .round, lineJoin: .round))
        }
    }

    // MARK: Fish

    private func draw(_ f: Fish, in context: inout GraphicsContext, size: CGSize, t: Double) {
        let span = Double(size.width) + 400
        let travelled = (t * f.speed + f.offset * span).truncatingRemainder(dividingBy: span)
        let along = f.movesRight ? travelled - 200 : Double(size.width) + 200 - travelled
        let x = along + f.dx
        let y = (f.baseY + f.dy) * Double(size.height) + sin(t * f.bobSpeed + f.offset * 10) * f.bobAmount
        let direction: CGFloat = f.movesRight ? 1 : -1
        let s = f.size
        let beat = CGFloat(sin(t * (5 + 3 * f.depth) + f.phase))

        // Far-away fish are hazy and bluish; close ones are vivid.
        let haze = 1 - f.depth
        let hue = f.depth < 0.3 ? 0.56 : f.hue
        let saturation = 0.25 + 0.55 * f.depth
        let brightness = 0.55 + 0.35 * f.depth
        let back = Color(hue: hue, saturation: saturation, brightness: brightness * 0.55)
        let side = Color(hue: hue, saturation: saturation, brightness: brightness)
        let belly = Color(hue: hue, saturation: saturation * 0.25, brightness: min(1, brightness + 0.3))
        let opacity = 0.35 + 0.65 * f.depth + haze * 0.0

        var c = context
        c.opacity = opacity
        c.translateBy(x: CGFloat(x), y: CGFloat(y))
        c.scaleBy(x: direction, y: 1)
        c.rotate(by: .radians(Double(beat) * 0.04))

        // Body, with a tail that beats from side to side
        var body = Path()
        body.move(to: CGPoint(x: s, y: 0))
        body.addCurve(to: CGPoint(x: -s * 0.7, y: -s * 0.14),
                      control1: CGPoint(x: s * 0.6, y: -s * 0.7), control2: CGPoint(x: -s * 0.2, y: -s * 0.6))
        body.addLine(to: CGPoint(x: -s * 1.4, y: -s * 0.55 + beat * s * 0.3))
        body.addLine(to: CGPoint(x: -s * 1.2, y: beat * s * 0.3))
        body.addLine(to: CGPoint(x: -s * 1.4, y: s * 0.55 + beat * s * 0.3))
        body.addLine(to: CGPoint(x: -s * 0.7, y: s * 0.14))
        body.addCurve(to: CGPoint(x: s, y: 0),
                      control1: CGPoint(x: -s * 0.2, y: s * 0.6), control2: CGPoint(x: s * 0.6, y: s * 0.65))
        body.closeSubpath()
        c.fill(body, with: .linearGradient(Gradient(stops: [
            .init(color: back, location: 0),
            .init(color: side, location: 0.5),
            .init(color: belly, location: 1)]),
            startPoint: CGPoint(x: 0, y: -s * 0.6), endPoint: CGPoint(x: 0, y: s * 0.6)))

        guard f.depth >= 0.3 else { return }   // distant fish are just silhouettes

        // Dorsal and belly fins
        var dorsal = Path()
        dorsal.move(to: CGPoint(x: s * 0.35, y: -s * 0.5))
        dorsal.addQuadCurve(to: CGPoint(x: -s * 0.45, y: -s * 0.38), control: CGPoint(x: -s * 0.05, y: -s * 1.0))
        dorsal.closeSubpath()
        c.fill(dorsal, with: .color(back))

        var pectoral = Path()
        pectoral.move(to: CGPoint(x: s * 0.3, y: s * 0.1))
        pectoral.addQuadCurve(to: CGPoint(x: -s * 0.15, y: s * 0.45 + beat * s * 0.05), control: CGPoint(x: s * 0.05, y: s * 0.5))
        pectoral.addLine(to: CGPoint(x: s * 0.0, y: s * 0.12))
        pectoral.closeSubpath()
        c.fill(pectoral, with: .color(side.opacity(0.85)))

        // Lateral line, gill and eye
        var line = Path()
        line.move(to: CGPoint(x: s * 0.5, y: -s * 0.02))
        line.addQuadCurve(to: CGPoint(x: -s * 0.7, y: 0), control: CGPoint(x: -s * 0.1, y: -s * 0.1))
        c.stroke(line, with: .color(.white.opacity(0.25)), lineWidth: max(1, s * 0.04))

        var gill = Path()
        gill.addArc(center: CGPoint(x: s * 0.28, y: 0), radius: s * 0.3,
                    startAngle: .degrees(-70), endAngle: .degrees(70), clockwise: false)
        c.stroke(gill, with: .color(.black.opacity(0.25)), lineWidth: max(1, s * 0.05))

        let eyeR = max(1.5, s * 0.09)
        c.fill(Path(ellipseIn: CGRect(x: s * 0.62 - eyeR, y: -s * 0.1 - eyeR, width: eyeR * 2, height: eyeR * 2)),
               with: .color(.white))
        c.fill(Path(ellipseIn: CGRect(x: s * 0.64 - eyeR * 0.55, y: -s * 0.1 - eyeR * 0.55,
                                      width: eyeR * 1.1, height: eyeR * 1.1)),
               with: .color(.black))
    }
}
