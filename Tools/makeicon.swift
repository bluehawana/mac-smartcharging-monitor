#!/usr/bin/env swift
//
// Renders the app icon at every size macOS asks for, then leaves an
// .iconset directory for `iconutil` to pack.
//
//   swift Tools/makeicon.swift && iconutil -c icns build/AppIcon.iconset \
//       -o Resources/AppIcon.icns
//
// The mark: a bolt sitting inside a gauge arc. The arc is the point —
// this app is about how much of the available power you are actually
// getting, so the icon shows a needle short of full rather than a plain
// bolt. Palette matches the app's instrument-panel theme.

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Palette

let ground      = CGColor(srgbRed: 0.055, green: 0.075, blue: 0.075, alpha: 1)
let groundHi    = CGColor(srgbRed: 0.110, green: 0.145, blue: 0.145, alpha: 1)

// MARK: - Drawing

func drawIcon(size: CGFloat, context ctx: CGContext) {
    let s = size

    // --- squircle ground ------------------------------------------------
    // macOS art sits inset from the canvas edge; ~10% keeps it consistent
    // with system icons in the Dock.
    let inset = s * 0.094
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = rect.width * 0.2237          // Apple's continuous-corner ratio

    let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    let groundGradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [groundHi, ground] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(groundGradient,
                           start: CGPoint(x: rect.midX, y: rect.maxY),
                           end: CGPoint(x: rect.midX, y: rect.minY),
                           options: [])
    ctx.restoreGState()

    // Hairline edge so the icon holds shape on a light Dock background.
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10))
    ctx.setLineWidth(max(s * 0.005, 0.5))
    ctx.strokePath()
    ctx.restoreGState()

    // --- gauge arc ------------------------------------------------------
    let centre = CGPoint(x: rect.midX, y: rect.midY)
    let arcR = rect.width * 0.335
    let lineW = rect.width * 0.072

    // Track: the full sweep that is available.
    ctx.saveGState()
    ctx.setLineCap(.round)
    ctx.setLineWidth(lineW)
    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10))
    ctx.addArc(center: centre, radius: arcR,
               startAngle: .pi * 1.25, endAngle: .pi * -0.25,
               clockwise: true)
    ctx.strokePath()
    ctx.restoreGState()

    // Fill: how much of it you are getting. Deliberately short of full.
    ctx.saveGState()
    ctx.setLineCap(.round)
    ctx.setLineWidth(lineW)
    ctx.setStrokeColor(CGColor(srgbRed: 0.31, green: 0.76, blue: 0.85, alpha: 1))
    ctx.addArc(center: centre, radius: arcR,
               startAngle: .pi * 1.25, endAngle: .pi * 0.30,
               clockwise: true)
    ctx.strokePath()
    ctx.restoreGState()

    // --- bolt -----------------------------------------------------------
    // Normalised polygon, y measured downward, then flipped into the
    // CoreGraphics bottom-left origin.
    // Kept deliberately chunky: a slender bolt vanishes at the 16 px
    // menu-bar and Finder sizes.
    let boltPoints: [(CGFloat, CGFloat)] = [
        (0.620, 0.030), (0.180, 0.570), (0.430, 0.570),
        (0.380, 0.970), (0.820, 0.430), (0.570, 0.430)
    ]

    let boltBox = rect.insetBy(dx: rect.width * 0.290, dy: rect.height * 0.225)
    let bolt = CGMutablePath()
    for (i, p) in boltPoints.enumerated() {
        let pt = CGPoint(x: boltBox.minX + p.0 * boltBox.width,
                         y: boltBox.maxY - p.1 * boltBox.height)
        if i == 0 { bolt.move(to: pt) } else { bolt.addLine(to: pt) }
    }
    bolt.closeSubpath()

    ctx.saveGState()
    ctx.addPath(bolt)
    ctx.clip()
    let boltGradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(srgbRed: 0.42, green: 0.85, blue: 0.78, alpha: 1),
            CGColor(srgbRed: 0.28, green: 0.72, blue: 0.86, alpha: 1)
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(boltGradient,
                           start: CGPoint(x: boltBox.minX, y: boltBox.maxY),
                           end: CGPoint(x: boltBox.maxX, y: boltBox.minY),
                           options: [])
    ctx.restoreGState()
}

// MARK: - Output

func render(size: Int) -> CGImage? {
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: size, height: size,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    drawIcon(size: CGFloat(size), context: ctx)
    return ctx.makeImage()
}

func write(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let outDir = URL(fileURLWithPath: "build/AppIcon.iconset")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

// (logical size, scale) — the set macOS expects in an .iconset
let variants: [(Int, Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2),
    (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)
]

for (logical, scale) in variants {
    let pixels = logical * scale
    guard let img = render(size: pixels) else {
        FileHandle.standardError.write(Data("failed at \(pixels)px\n".utf8))
        exit(1)
    }
    let name = scale == 1 ? "icon_\(logical)x\(logical).png"
                          : "icon_\(logical)x\(logical)@2x.png"
    write(img, to: outDir.appendingPathComponent(name))
}

// A standalone 1024px copy for the README and any store listing.
if let img = render(size: 1024) {
    write(img, to: URL(fileURLWithPath: "docs/images/icon.png"))
}

print("wrote \(variants.count) sizes to \(outDir.path)")
