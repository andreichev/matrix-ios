// Run from the repository root: swift test-support/render-app-icons.swift
// Vector mark shared with matrix-landing: eight squares around an open centre.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let resources = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Matrix Workspace/Resources")
let tiles = (0..<3).flatMap { row in
    (0..<3).compactMap { column -> CGRect? in
        guard row != 1 || column != 1 else { return nil }
        return CGRect(x: 206 + column * 234, y: 206 + row * 234, width: 144, height: 144)
    }
}
let variants = [
    ("AppIcon", "193d32", "d4ef99"),
    ("AppIcon-dark", "0b1f1a", "d4ef99"),
    ("AppIcon-tinted", "000000", "e0e0e0"),
]

func color(_ hex: String) -> CGColor {
    let value = UInt32(hex, radix: 16)!
    return CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [
        CGFloat((value >> 16) & 255) / 255,
        CGFloat((value >> 8) & 255) / 255,
        CGFloat(value & 255) / 255, 1,
    ])!
}

for (name, background, foreground) in variants {
    let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(color(background))
    context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    context.setFillColor(color(foreground))
    tiles.forEach { context.fill($0) }
    let file = resources.appendingPathComponent("Assets.xcassets/AppIcon.appiconset/\(name).png")
    let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Could not write \(file.path)") }
}

let squares = tiles.map {
    "    <rect x=\"\(Int($0.minX))\" y=\"\(Int($0.minY))\" width=\"144\" height=\"144\" />"
}.joined(separator: "\n")
let svg = """
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <rect width="1024" height="1024" fill="#193d32" />
  <g fill="#d4ef99">
\(squares)
  </g>
</svg>

"""
try svg.write(to: resources.appendingPathComponent("AppIcon.svg"), atomically: true, encoding: .utf8)
