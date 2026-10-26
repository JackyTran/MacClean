// Generates the MacClean app icon with CoreGraphics.
//
// Usage:
//   swift scripts/make-icon.swift <output.png>     # 1024px master PNG
//   swift scripts/make-icon.swift --iconset <dir>   # full macOS AppIcon set
//
// The artwork is vector, so every size is rendered natively instead of being
// downscaled from the master — small icons stay crisp.
//
// Design: a trash bin on Apple's continuous-curvature icon shape. The bin's
// slots are knockouts, so the blue background shows through them.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Geometry (1024-point design space)

private let canvas: CGFloat = 1024
private let shapeInset: CGFloat = 100                 // Apple grid: 824pt shape
private let squircleExponent: CGFloat = 5.0            // macOS squircle

/// All layout below is written top-down, the way the icon reads on screen.
/// CoreGraphics user space is y-up, so convert on the way into a path.
private func uy(_ topDown: CGFloat) -> CGFloat { canvas - topDown }

private func sign(_ v: CGFloat) -> CGFloat { v < 0 ? -1 : 1 }

/// Apple's continuous-curvature macOS icon shape (a superellipse).
private func squirclePath(_ rect: CGRect, exponent: CGFloat = squircleExponent) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = rect.midX + a * sign(ct) * pow(abs(ct), 2 / exponent)
        let y = rect.midY + b * sign(st) * pow(abs(st), 2 / exponent)
        if i == 0 {
            path.move(to: CGPoint(x: x, y: y))
        } else {
            path.addLine(to: CGPoint(x: x, y: y))
        }
    }
    path.closeSubpath()
    return path
}

/// A vertical capsule — the bin's see-through slots.
private func capsule(x: CGFloat, topDownY0: CGFloat, topDownY1: CGFloat, width: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: x - width / 2, y: uy(topDownY1),
                               width: width, height: topDownY1 - topDownY0),
           cornerWidth: width / 2, cornerHeight: width / 2, transform: nil)
}

/// The tapered bin body: wide at the rim, narrow at the base, rounded bottom.
private func binBodyPath() -> CGPath {
    let path = CGMutablePath()
    let cx: CGFloat = 512
    let rimY = uy(354)          // top of the body (widest)
    let baseY = uy(750)         // bottom of the body (narrowest)
    let rimHalf: CGFloat = 165
    let baseHalf: CGFloat = 123
    let corner: CGFloat = 46

    path.move(to: CGPoint(x: cx - rimHalf, y: rimY))
    path.addLine(to: CGPoint(x: cx + rimHalf, y: rimY))
    path.addLine(to: CGPoint(x: cx + baseHalf, y: baseY + corner))
    path.addQuadCurve(to: CGPoint(x: cx + baseHalf - corner, y: baseY),
                      control: CGPoint(x: cx + baseHalf, y: baseY))
    path.addLine(to: CGPoint(x: cx - baseHalf + corner, y: baseY))
    path.addQuadCurve(to: CGPoint(x: cx - baseHalf, y: baseY + corner),
                      control: CGPoint(x: cx - baseHalf, y: baseY))
    path.closeSubpath()
    return path
}

// MARK: - Colors

private let bgTop = CGColor(srgbRed: 0.45, green: 0.57, blue: 1.00, alpha: 1)
private let bgMid = CGColor(srgbRed: 0.20, green: 0.36, blue: 0.93, alpha: 1)
private let bgBottom = CGColor(srgbRed: 0.03, green: 0.65, blue: 0.79, alpha: 1)
private let binWhite = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.97)

// MARK: - Drawing

private func drawIcon(size: CGFloat, detailed: Bool) -> CGImage {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
    ctx.scaleBy(x: size / canvas, y: size / canvas)
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    let shapeRect = CGRect(x: shapeInset, y: shapeInset,
                           width: canvas - 2 * shapeInset, height: canvas - 2 * shapeInset)
    let shape = squirclePath(shapeRect)
    let bg = CGGradient(colorsSpace: cs, colors: [bgTop, bgMid, bgBottom] as CFArray,
                        locations: [0.0, 0.55, 1.0])!

    // --- background: diagonal gradient clipped to the squircle ---
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    ctx.drawLinearGradient(bg,
                           start: CGPoint(x: shapeRect.minX, y: shapeRect.maxY),
                           end: CGPoint(x: shapeRect.maxX, y: shapeRect.minY),
                           options: [])

    // Soft top-left sheen — a radial falloff, so there is no hard edge.
    let sheen = CGGradient(colorsSpace: cs, colors: [
        CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.30),
        CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.0),
    ] as CFArray, locations: [0.0, 1.0])!
    let sheenCenter = CGPoint(x: shapeRect.midX - shapeRect.width * 0.24,
                              y: shapeRect.midY + shapeRect.height * 0.28)
    ctx.drawRadialGradient(sheen, startCenter: sheenCenter, startRadius: 0,
                           endCenter: sheenCenter, endRadius: shapeRect.width * 0.82,
                           options: [.drawsAfterEndLocation])

    // Gentle shading at the base gives the squircle some weight.
    let floor = CGGradient(colorsSpace: cs, colors: [
        CGColor(srgbRed: 0.02, green: 0.05, blue: 0.15, alpha: 0.00),
        CGColor(srgbRed: 0.02, green: 0.05, blue: 0.15, alpha: 0.22),
    ] as CFArray, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(floor,
                           start: CGPoint(x: shapeRect.midX, y: shapeRect.minY + shapeRect.height * 0.55),
                           end: CGPoint(x: shapeRect.midX, y: shapeRect.minY),
                           options: [])
    ctx.restoreGState()

    // --- glyph: bin (handle above the lid, body tapering down to the base) ---
    let body = binBodyPath()
    let lid = CGPath(roundedRect: CGRect(x: 296, y: uy(348), width: 432, height: 70),
                     cornerWidth: 35, cornerHeight: 35, transform: nil)
    let handle = CGPath(roundedRect: CGRect(x: 464, y: uy(282), width: 96, height: 66),
                        cornerWidth: 28, cornerHeight: 28, transform: nil)

    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 34,
                  color: CGColor(srgbRed: 0.02, green: 0.05, blue: 0.18, alpha: 0.30))
    ctx.setFillColor(binWhite)
    ctx.addPath(body); ctx.fillPath()

    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 20,
                  color: CGColor(srgbRed: 0.05, green: 0.12, blue: 0.35, alpha: 0.28))
    ctx.addPath(lid); ctx.fillPath()

    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 16,
                  color: CGColor(srgbRed: 0.05, green: 0.12, blue: 0.35, alpha: 0.25))
    ctx.addPath(handle); ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    // --- slots: knock the body out so the background shows through ---
    let slotCenters: [CGFloat] = detailed ? [440, 512, 584] : []
    for cx in slotCenters {
        ctx.saveGState()
        ctx.addPath(capsule(x: cx, topDownY0: 424, topDownY1: 676, width: 30))
        ctx.clip()
        ctx.setBlendMode(.copy)
        ctx.drawLinearGradient(bg,
                               start: CGPoint(x: shapeRect.minX, y: shapeRect.maxY),
                               end: CGPoint(x: shapeRect.maxX, y: shapeRect.minY),
                               options: [])
        ctx.setBlendMode(.normal)
        ctx.restoreGState()
    }

    // --- body shading: an even-odd clip leaves the knocked-out slots untouched ---
    ctx.saveGState()
    ctx.addPath(body)
    for cx in slotCenters {
        ctx.addPath(capsule(x: cx, topDownY0: 424, topDownY1: 676, width: 30))
    }
    ctx.clip(using: .evenOdd)
    let shade = CGGradient(colorsSpace: cs, colors: [
        CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10),
        CGColor(srgbRed: 0.72, green: 0.82, blue: 1.00, alpha: 0.10),
    ] as CFArray, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(shade,
                           start: CGPoint(x: 512, y: uy(354)),
                           end: CGPoint(x: 512, y: uy(750)),
                           options: [])
    ctx.restoreGState()

    // --- sparkles: "clean" ---
    if detailed {
        func sparkle(_ center: CGPoint, _ r: CGFloat, _ alpha: CGFloat) {
            ctx.saveGState()
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha))
            let p = CGMutablePath()
            p.move(to: CGPoint(x: center.x, y: center.y + r))
            p.addQuadCurve(to: CGPoint(x: center.x + r, y: center.y),
                           control: CGPoint(x: center.x + 0.18 * r, y: center.y + 0.18 * r))
            p.addQuadCurve(to: CGPoint(x: center.x, y: center.y - r),
                           control: CGPoint(x: center.x + 0.18 * r, y: center.y - 0.18 * r))
            p.addQuadCurve(to: CGPoint(x: center.x - r, y: center.y),
                           control: CGPoint(x: center.x - 0.18 * r, y: center.y - 0.18 * r))
            p.addQuadCurve(to: CGPoint(x: center.x, y: center.y + r),
                           control: CGPoint(x: center.x - 0.18 * r, y: center.y + 0.18 * r))
            ctx.addPath(p); ctx.fillPath()
            ctx.restoreGState()
        }
        sparkle(CGPoint(x: 800, y: uy(196)), 54, 0.95)
        sparkle(CGPoint(x: 858, y: uy(372)), 32, 0.85)
        sparkle(CGPoint(x: 700, y: uy(856)), 24, 0.75)
    }

    return ctx.makeImage()!
}

// MARK: - Output

private func writePNG(_ image: CGImage, to url: URL) throws {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "make-icon", code: 1)
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        throw NSError(domain: "make-icon", code: 2)
    }
}

private let iconSetEntries: [(name: String, size: CGFloat, slot: String, scale: String)] = [
    ("icon_16x16",      16,  "16x16",   "1x"),
    ("icon_16x16@2x",   32,  "16x16",   "2x"),
    ("icon_32x32",      32,  "32x32",   "1x"),
    ("icon_32x32@2x",   64,  "32x32",   "2x"),
    ("icon_128x128",    128, "128x128", "1x"),
    ("icon_128x128@2x", 256, "128x128", "2x"),
    ("icon_256x256",    256, "256x256", "1x"),
    ("icon_256x256@2x", 512, "256x256", "2x"),
    ("icon_512x512",    512, "512x512", "1x"),
    ("icon_512x512@2x", 1024, "512x512", "2x"),
]

private func writeIconSet(to dir: URL) throws {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    var entries: [String] = []
    for entry in iconSetEntries {
        let image = drawIcon(size: entry.size, detailed: entry.size >= 64)
        try writePNG(image, to: dir.appendingPathComponent("\(entry.name).png"))
        entries.append("""
        {
          "filename" : "\(entry.name).png",
          "idiom" : "mac",
          "scale" : "\(entry.scale)",
          "size" : "\(entry.slot)"
        }
        """)
    }

    let contents = """
    {
      "images" : [
    \(entries.joined(separator: ",\n"))
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }

    """
    try contents.write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    print("wrote \(iconSetEntries.count) icons to \(dir.path)")
}

// MARK: - Main

let args = CommandLine.arguments
if args.count >= 3 && args[1] == "--iconset" {
    try writeIconSet(to: URL(fileURLWithPath: args[2]))
} else {
    let out = args.count > 1 ? args[1] : "icon_1024.png"
    try writePNG(drawIcon(size: canvas, detailed: true), to: URL(fileURLWithPath: out))
    print("wrote \(out)")
}
