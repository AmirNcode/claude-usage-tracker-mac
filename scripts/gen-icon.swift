#!/usr/bin/env swift
// Generates Resources/AppIcon.icns — a circular usage-gauge icon.
// Run via scripts/build-icon.sh (renders an .iconset, then iconutil).
import AppKit
import CoreGraphics

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func render(_ size: Int) -> CGImage {
    let s = CGFloat(size)
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setShouldAntialias(true)

    // Squircle-ish background with a graphite gradient.
    let margin = s * 0.045
    let rect = CGRect(x: margin, y: margin, width: s - 2 * margin, height: s - 2 * margin)
    let radius = rect.width * 0.2237
    let bg = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.addPath(bg)
    ctx.clip()
    let grad = CGGradient(colorsSpace: cs, colors: [
        CGColor(red: 0.20, green: 0.20, blue: 0.22, alpha: 1),
        CGColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])
    // Subtle top sheen.
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.05))
    ctx.fill(CGRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2))
    ctx.restoreGState()

    // Gauge.
    let center = CGPoint(x: s / 2, y: s / 2)
    let gaugeR = s * 0.30
    let lw = s * 0.105
    ctx.setLineCap(.round)

    // Track ring.
    ctx.setLineWidth(lw)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.14))
    ctx.addArc(center: center, radius: gaugeR, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()

    // Progress arc (~73%) in Claude coral, starting at top going clockwise.
    let start = CGFloat.pi / 2
    let sweep = CGFloat(0.73) * .pi * 2
    ctx.setStrokeColor(CGColor(red: 0.85, green: 0.46, blue: 0.34, alpha: 1)) // #D97757
    ctx.setLineWidth(lw)
    ctx.addArc(center: center, radius: gaugeR, startAngle: start, endAngle: start - sweep, clockwise: true)
    ctx.strokePath()

    // Center dot for a clean focal point.
    ctx.setFillColor(CGColor(red: 0.85, green: 0.46, blue: 0.34, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: center.x - s * 0.045, y: center.y - s * 0.045,
                               width: s * 0.09, height: s * 0.09))

    return ctx.makeImage()!
}

func write(_ image: CGImage, _ name: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}

// iconset variants.
let specs: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]
var cache: [Int: CGImage] = [:]
for (size, name) in specs {
    let img = cache[size] ?? render(size)
    cache[size] = img
    write(img, name)
}
print("Wrote \(specs.count) icon images to \(outDir)")
