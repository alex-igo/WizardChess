import SwiftUI
import UIKit

/// Background choices for the game.
enum BackgroundTheme: String, CaseIterable, Identifiable {
    case starryNight = "Starry Night"
    case snowyNight = "Snowy Night"
    case sunset = "Sunset"
    case ocean = "Ocean"
    case space = "Outer Space"
    case custom = "Custom Color"

    var id: String { rawValue }

    /// Themes that have a "you lose" attack: a shark, a spaceship or a dragon.
    var hasAttack: Bool {
        switch self {
        case .ocean, .space, .sunset, .snowyNight: return true
        case .starryNight, .custom: return false
        }
    }
}

extension UIColor {
    /// "#RRGGBB" (or "RRGGBB"). Falls back to a dark blue if the text isn't valid.
    convenience init(hex: String) {
        var text = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if text.count != 6 { text = "1B2A41" }
        var value: UInt64 = 0
        Scanner(string: text).scanHexInt64(&value)
        self.init(red: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255,
                  alpha: 1)
    }

    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    /// 0 (black) ... 1 (white), roughly how bright the colour looks.
    var perceivedBrightness: CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.299 * r + 0.587 * g + 0.114 * b
    }
}

/// A random number generator that gives the same sequence every time, so the star field
/// looks identical in the 2D and 3D views and from one launch to the next.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Draws the background images. Everything is generated in code, so there are no image files to add.
enum SkyRenderer {
    nonisolated(unsafe) private static var cache: [String: UIImage] = [:]

    /// A background image of the given size. The 3D view asks for a 2:1 image, which SceneKit
    /// wraps around the whole scene like a sky, so the stars slide past as you orbit the board.
    static func image(for theme: BackgroundTheme, customHex: String, size: CGSize) -> UIImage {
        if theme == .custom {
            return render(theme, customHex, size)  // plain colour: cheap, and not worth caching
        }
        let key = "\(theme.rawValue)|\(Int(size.width))x\(Int(size.height))"
        if let cached = cache[key] { return cached }
        let image = render(theme, customHex, size)
        cache[key] = image
        return image
    }

    // Top, middle (the horizon glow) and bottom colours of the sky.
    private static func colors(for theme: BackgroundTheme, customHex: String) -> [UIColor] {
        func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor { UIColor(red: r, green: g, blue: b, alpha: 1) }
        switch theme {
        case .starryNight:
            return [rgb(0.01, 0.02, 0.09), rgb(0.06, 0.09, 0.26), rgb(0.01, 0.02, 0.08)]
        case .snowyNight:
            return [rgb(0.01, 0.04, 0.12), rgb(0.05, 0.17, 0.30), rgb(0.02, 0.07, 0.14)]
        case .sunset:
            return [rgb(0.10, 0.06, 0.22), rgb(0.95, 0.48, 0.28), rgb(0.12, 0.07, 0.20)]
        case .ocean:
            return [rgb(0.01, 0.06, 0.15), rgb(0.06, 0.50, 0.60), rgb(0.01, 0.07, 0.14)]
        case .space:
            return [rgb(0.00, 0.00, 0.03), rgb(0.07, 0.03, 0.17), rgb(0.00, 0.01, 0.05)]
        case .custom:
            let color = UIColor(hex: customHex)
            return [color, color, color]
        }
    }

    private static func render(_ theme: BackgroundTheme, _ customHex: String, _ size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let stops = colors(for: theme, customHex: customHex)
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: stops.map { $0.cgColor } as CFArray,
                                      locations: [0, 0.5, 1])!
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            if theme == .starryNight || theme == .space { drawStars(cg, size) }
            if theme == .space { drawSpaceScenery(cg, size) }
            if theme == .snowyNight { drawStars(cg, size); drawAurora(cg, size); drawRidges(cg, size, snowy: true) }
            if theme == .sunset { drawSunsetScenery(cg, size) }
        }
    }

    /// Nebula clouds, a ringed planet and a distant moon, drawn over the stars.
    private static func drawSpaceScenery(_ cg: CGContext, _ size: CGSize) {
        func glow(_ center: CGPoint, radius: CGFloat, color: UIColor, alpha: CGFloat) {
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: [color.withAlphaComponent(alpha).cgColor,
                                               color.withAlphaComponent(0).cgColor] as CFArray,
                                      locations: [0, 1])!
            cg.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                  endCenter: center, endRadius: radius, options: [])
        }
        let w = size.width, h = size.height
        let unit = max(w, h) / 1000

        // Nebula: a few big soft clouds of violet, magenta and teal.
        glow(CGPoint(x: w * 0.25, y: h * 0.30), radius: w * 0.45, color: UIColor(red: 0.55, green: 0.15, blue: 0.80, alpha: 1), alpha: 0.30)
        glow(CGPoint(x: w * 0.80, y: h * 0.62), radius: w * 0.40, color: UIColor(red: 0.85, green: 0.20, blue: 0.55, alpha: 1), alpha: 0.22)
        glow(CGPoint(x: w * 0.45, y: h * 0.80), radius: w * 0.38, color: UIColor(red: 0.10, green: 0.55, blue: 0.75, alpha: 1), alpha: 0.20)

        // A big planet with a lit edge and a ring.
        let planet = CGPoint(x: w * 0.78, y: h * 0.32)
        let r = 70 * unit
        cg.saveGState()
        cg.addEllipse(in: CGRect(x: planet.x - r, y: planet.y - r, width: r * 2, height: r * 2))
        cg.clip()
        let body = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [UIColor(red: 0.95, green: 0.70, blue: 0.45, alpha: 1).cgColor,
                                       UIColor(red: 0.55, green: 0.25, blue: 0.25, alpha: 1).cgColor,
                                       UIColor(red: 0.08, green: 0.03, blue: 0.10, alpha: 1).cgColor] as CFArray,
                              locations: [0, 0.55, 1])!
        cg.drawLinearGradient(body, start: CGPoint(x: planet.x - r, y: planet.y - r),
                              end: CGPoint(x: planet.x + r, y: planet.y + r), options: [])
        cg.restoreGState()
        cg.saveGState()
        cg.translateBy(x: planet.x, y: planet.y)
        cg.rotate(by: -0.35)
        cg.setStrokeColor(UIColor(red: 0.95, green: 0.82, blue: 0.62, alpha: 0.55).cgColor)
        cg.setLineWidth(5 * unit)
        cg.strokeEllipse(in: CGRect(x: -r * 1.9, y: -r * 0.38, width: r * 3.8, height: r * 0.76))
        cg.restoreGState()

        // A small cratered moon.
        let moon = CGPoint(x: w * 0.18, y: h * 0.70)
        let m = 22 * unit
        let moonGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: [UIColor(white: 0.85, alpha: 1).cgColor,
                                               UIColor(white: 0.12, alpha: 1).cgColor] as CFArray,
                                      locations: [0, 1])!
        cg.saveGState()
        cg.addEllipse(in: CGRect(x: moon.x - m, y: moon.y - m, width: m * 2, height: m * 2))
        cg.clip()
        cg.drawLinearGradient(moonGradient, start: CGPoint(x: moon.x - m, y: moon.y - m),
                              end: CGPoint(x: moon.x + m, y: moon.y + m), options: [])
        cg.restoreGState()
    }

    /// Layered mountain silhouettes along the horizon. `snowy` gives them pale blue snowy tops.
    private static func drawRidges(_ cg: CGContext, _ size: CGSize, snowy: Bool) {
        let w = size.width, h = size.height
        var rng = SeededRandom(seed: snowy ? 7 : 11)
        func random() -> CGFloat { CGFloat.random(in: 0..<1, using: &rng) }

        // (baseline, how tall the peaks get, colour)
        let layers: [(CGFloat, CGFloat, UIColor)] = snowy
            ? [(0.66, 0.10, UIColor(red: 0.08, green: 0.16, blue: 0.28, alpha: 1)),
               (0.72, 0.09, UIColor(red: 0.04, green: 0.09, blue: 0.17, alpha: 1))]
            : [(0.62, 0.08, UIColor(red: 0.30, green: 0.12, blue: 0.22, alpha: 1)),
               (0.70, 0.07, UIColor(red: 0.12, green: 0.05, blue: 0.12, alpha: 1))]
        for (baseline, peak, color) in layers {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: h))
            var x: CGFloat = 0
            var y = h * baseline
            path.addLine(to: CGPoint(x: 0, y: y))
            while x < w {
                x += w * (0.04 + 0.05 * random())
                y = h * (baseline - peak * random())
                path.addLine(to: CGPoint(x: min(x, w), y: y))
            }
            path.addLine(to: CGPoint(x: w, y: h))
            path.closeSubpath()
            cg.setFillColor(color.cgColor)
            cg.addPath(path)
            cg.fillPath()
            if snowy {
                // A thin pale rim of snow on the ridge line.
                cg.setStrokeColor(UIColor(red: 0.75, green: 0.88, blue: 1.0, alpha: 0.35).cgColor)
                cg.setLineWidth(max(w / 500, 1))
                cg.addPath(path)
                cg.strokePath()
            }
        }
    }

    /// Northern lights: soft green and teal curtains high in the sky.
    private static func drawAurora(_ cg: CGContext, _ size: CGSize) {
        let w = size.width, h = size.height
        let columns = 160
        let columnWidth = w / CGFloat(columns)
        let ribbons: [(CGFloat, CGFloat, UIColor)] = [
            (0.28, 0.0, UIColor(red: 0.20, green: 1.00, blue: 0.55, alpha: 1)),
            (0.35, 2.1, UIColor(red: 0.20, green: 0.80, blue: 0.95, alpha: 1)),
            (0.22, 4.0, UIColor(red: 0.55, green: 0.40, blue: 0.95, alpha: 1))
        ]
        for (centre, phase, color) in ribbons {
            for i in 0..<columns {
                let u = CGFloat(i) / CGFloat(columns)
                let slow: CGFloat = sin(u * 2 * CGFloat.pi * 1.3 + phase) * 0.06
                let fast: CGFloat = sin(u * 2 * CGFloat.pi * 3.1 + phase * 2) * 0.025
                let bottom: CGFloat = h * (centre + slow + fast)
                let pulse: CGFloat = 0.5 + 0.5 * sin(u * 2 * CGFloat.pi * 2.3 + phase * 1.7)
                let height: CGFloat = h * (0.10 + 0.10 * pulse)
                let rect = CGRect(x: CGFloat(i) * columnWidth, y: bottom - height, width: columnWidth + 1, height: height)
                let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                          colors: [color.withAlphaComponent(0).cgColor,
                                                   color.withAlphaComponent(0.30).cgColor] as CFArray,
                                          locations: [0, 1])!
                cg.saveGState()
                cg.clip(to: rect)
                cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])
                cg.restoreGState()
            }
        }
    }

    /// A low glowing sun, streaks of cloud and dark mountains.
    private static func drawSunsetScenery(_ cg: CGContext, _ size: CGSize) {
        let w = size.width, h = size.height
        let unit = max(w, h) / 1000
        func glow(_ center: CGPoint, radius: CGFloat, color: UIColor, alpha: CGFloat) {
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: [color.withAlphaComponent(alpha).cgColor,
                                               color.withAlphaComponent(0).cgColor] as CFArray,
                                      locations: [0, 1])!
            cg.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                  endCenter: center, endRadius: radius, options: [])
        }

        // The sun, with a wide warm halo.
        let sun = CGPoint(x: w * 0.5, y: h * 0.50)
        glow(sun, radius: w * 0.55, color: UIColor(red: 1.0, green: 0.55, blue: 0.20, alpha: 1), alpha: 0.55)
        glow(sun, radius: 140 * unit, color: UIColor(red: 1.0, green: 0.85, blue: 0.50, alpha: 1), alpha: 0.9)
        let r = 52 * unit
        cg.setFillColor(UIColor(red: 1.0, green: 0.93, blue: 0.70, alpha: 1).cgColor)
        cg.fillEllipse(in: CGRect(x: sun.x - r, y: sun.y - r, width: r * 2, height: r * 2))

        // Long streaks of cloud lit pink and orange from below.
        var rng = SeededRandom(seed: 99)
        func random() -> CGFloat { CGFloat.random(in: 0..<1, using: &rng) }
        for i in 0..<9 {
            let center = CGPoint(x: w * random(), y: h * (0.22 + 0.34 * random()))
            let warm = i % 2 == 0
            let color = warm ? UIColor(red: 1.0, green: 0.55, blue: 0.35, alpha: 1)
                             : UIColor(red: 0.85, green: 0.35, blue: 0.55, alpha: 1)
            cg.saveGState()
            cg.translateBy(x: center.x, y: center.y)
            cg.scaleBy(x: 3.2, y: 0.28)
            glow(.zero, radius: (60 + 70 * random()) * unit, color: color, alpha: 0.45)
            cg.restoreGState()
        }

        drawRidges(cg, size, snowy: false)
    }

    private static func drawStars(_ cg: CGContext, _ size: CGSize) {
        var rng = SeededRandom(seed: 42)
        let area = size.width * size.height
        let unit = max(max(size.width, size.height) / 1000, 0.8)  // star size scales with the image

        func random() -> CGFloat { CGFloat.random(in: 0..<1, using: &rng) }
        func gaussian() -> CGFloat {
            let u1 = max(random(), 0.0001), u2 = random()
            return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
        }
        func dot(_ x: CGFloat, _ y: CGFloat, radius: CGFloat, color: UIColor, alpha: CGFloat) {
            cg.setFillColor(color.withAlphaComponent(alpha).cgColor)
            cg.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
        }

        // A faint milky-way band: lots of tiny dim stars bunched along a gentle wave.
        let bandColor = UIColor(red: 0.75, green: 0.82, blue: 1.0, alpha: 1)
        for _ in 0..<max(Int(area / 350), 60) {
            let x = random() * size.width
            let centre = size.height * (0.5 + 0.18 * sin(x / size.width * 2 * .pi + 0.8))
            let y = centre + gaussian() * size.height * 0.09
            dot(x, y, radius: (0.35 + random() * 0.5) * unit, color: bandColor, alpha: 0.12 + random() * 0.30)
        }

        // The stars proper: mostly dim, a few bright, with a soft glow on the brightest.
        let tints = [UIColor.white,
                     UIColor(red: 0.80, green: 0.88, blue: 1.0, alpha: 1),
                     UIColor(red: 1.0, green: 0.94, blue: 0.80, alpha: 1)]
        let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [UIColor(white: 1, alpha: 0.35).cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray,
                              locations: [0, 1])!
        for _ in 0..<max(Int(area / 1800), 40) {
            let x = random() * size.width
            let y = random() * size.height
            let brightness = pow(random(), 3)
            let tint = tints[Int(random() * CGFloat(tints.count)) % tints.count]
            dot(x, y, radius: (0.5 + 1.6 * brightness) * unit, color: tint, alpha: 0.35 + 0.65 * brightness)
            if brightness > 0.85 {
                cg.drawRadialGradient(glow,
                                      startCenter: CGPoint(x: x, y: y), startRadius: 0,
                                      endCenter: CGPoint(x: x, y: y), endRadius: 7 * unit,
                                      options: [])
            }
        }
    }
}

/// The backdrop behind the 2D board and the menus.
struct ThemeBackgroundView: View {
    let theme: BackgroundTheme
    let customHex: String

    var body: some View {
        Image(uiImage: SkyRenderer.image(for: theme, customHex: customHex, size: CGSize(width: 800, height: 1600)))
            .resizable()
            .scaledToFill()
            .ignoresSafeArea()
    }
}
