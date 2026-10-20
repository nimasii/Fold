import Foundation
import CoreGraphics
import ImageIO

// Reproducible vector-built, opaque1024px masters. iOS supplies the outer icon mask.
// Run from the repository root: swift scripts/generate-app-icon.swift
struct Palette {
    let name: String, background: String, frame: String, play: String
}
let palettes = [
    Palette(name: "AppIcon", background: "E3443C", frame: "FFFFFF", play: "FFFFFF"),
    Palette(name: "AppIcon-dark", background: "151B22", frame: "F16C62", play: "FFFFFF"),
    Palette(name: "AppIcon-tinted", background: "222222", frame: "F5F5F5", play: "F5F5F5")
]
func color(_ hex: String) -> CGColor {
    let n = UInt32(hex, radix: 16)!
    return CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [
        CGFloat((n >> 16) & 255) / 255, CGFloat((n >> 8) & 255) / 255, CGFloat(n & 255) / 255, 1])!
}
let asset = URL(fileURLWithPath: "Fold/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
for p in palettes {
    let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
        bytesPerRow: 4096, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(color(p.background)); context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    context.setStrokeColor(color(p.frame)); context.setLineWidth(38)
    context.addPath(CGPath(roundedRect: CGRect(x: 190, y: 340, width: 644, height: 436), cornerWidth: 126, cornerHeight: 126, transform: nil))
    context.strokePath()
    context.setLineWidth(34); context.setLineCap(.round)
    context.move(to: CGPoint(x: 347, y: 250)); context.addLine(to: CGPoint(x: 677, y: 250)); context.strokePath()
    context.setFillColor(color(p.play))
    context.move(to: CGPoint(x: 464, y: 450))
    context.addCurve(to: CGPoint(x: 478, y: 442), control1: CGPoint(x: 464, y: 441), control2: CGPoint(x: 471, y: 438))
    context.addLine(to: CGPoint(x: 655, y: 550))
    context.addCurve(to: CGPoint(x: 655, y: 566), control1: CGPoint(x: 663, y: 555), control2: CGPoint(x: 663, y: 561))
    context.addLine(to: CGPoint(x: 478, y: 674))
    context.addCurve(to: CGPoint(x: 464, y: 666), control1: CGPoint(x: 471, y: 678), control2: CGPoint(x: 464, y: 675))
    context.closePath(); context.fillPath()
    let destination = CGImageDestinationCreateWithURL(asset.appendingPathComponent(p.name + ".png") as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("PNG write failed") }
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
      <rect width="1024" height="1024" fill="#\(p.background)"/>
      <g transform="translate(0 1024) scale(1 -1)">
        <rect x="190" y="340" width="644" height="436" rx="126" fill="none" stroke="#\(p.frame)" stroke-width="38"/>
        <path d="M347 250H677" stroke="#\(p.frame)" stroke-width="34" stroke-linecap="round"/>
        <path d="M464 450C464 441 471 438 478 442L655 550C663 555 663 561 655 566L478 674C471 678 464 675 464 666Z" fill="#\(p.play)"/>
      </g>
    </svg>
    """
    try svg.write(toFile: "docs/branding/\(p.name).svg", atomically: true, encoding: .utf8)
}
