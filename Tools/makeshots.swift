#!/usr/bin/env swift
//
// Builds Mac App Store / marketing screenshots from the real app captures.
//
//   swift Tools/makeshots.swift
//
// Mac App Store wants 16:10 landscape at one of 1280x800, 1440x900,
// 2560x1600 or 2880x1800, flattened RGB with no alpha. We render at
// 2880x1800 and downscale, so one pass covers every accepted size.
//
// Apple requires the shot to show the real interface, so these composite the
// actual captures rather than illustrating them. The headline is the only
// thing added.

import Foundation
import AppKit
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

// MARK: - Palette (matches the app's instrument-panel theme)

let bgTop    = CGColor(srgbRed: 0.075, green: 0.098, blue: 0.098, alpha: 1)
let bgBottom = CGColor(srgbRed: 0.043, green: 0.055, blue: 0.055, alpha: 1)
let ink      = CGColor(srgbRed: 0.965, green: 0.980, blue: 0.976, alpha: 1)
let accent   = CGColor(srgbRed: 0.31,  green: 0.76,  blue: 0.85,  alpha: 1)
let dim      = CGColor(srgbRed: 0.58,  green: 0.64,  blue: 0.63,  alpha: 1)

// MARK: - Config

/// Slides are described in JSON so this tool works for any Mac app, not just
/// this one. Pass a path as the first argument, or drop a `screenshots.json`
/// beside the project root.
struct Slide: Decodable {
    let file: String          // capture, relative to `imageDir`
    let headline: String
    let subhead: String
    let tint: [Double]        // r, g, b in 0...1

    var tintColor: CGColor {
        CGColor(srgbRed: tint.count > 0 ? tint[0] : 0.3,
                green:   tint.count > 1 ? tint[1] : 0.7,
                blue:    tint.count > 2 ? tint[2] : 0.8, alpha: 1)
    }
}

struct ShotConfig: Decodable {
    let imageDir: String
    let outputDir: String
    let slides: [Slide]
}

let configPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "screenshots.json"

guard let configData = FileManager.default.contents(atPath: configPath),
      let config = try? JSONDecoder().decode(ShotConfig.self, from: configData)
else {
    FileHandle.standardError.write(Data("""
        cannot read \(configPath)

        Expected JSON shaped like:
        {
          "imageDir": "docs/images",
          "outputDir": "docs/appstore",
          "slides": [
            { "file": "shot.png", "headline": "Big claim",
              "subhead": "One supporting sentence.", "tint": [0.31, 0.76, 0.85] }
          ]
        }

        """.utf8))
    exit(1)
}

let slides = config.slides

// MARK: - Text

func font(_ size: CGFloat, weight: NSFont.Weight) -> CTFont {
    NSFont.systemFont(ofSize: size, weight: weight) as CTFont
}

/// Height this text needs at the given width. Used to stack blocks without
/// leaving gaps when a headline runs short.
func measure(_ text: String, font f: CTFont, width: CGFloat, leading: CGFloat) -> CGFloat {
    let style = NSMutableParagraphStyle()
    style.lineSpacing = leading
    let attributed = NSAttributedString(string: text, attributes: [
        .font: f, .paragraphStyle: style
    ])
    let fs = CTFramesetterCreateWithAttributedString(attributed)
    let size = CTFramesetterSuggestFrameSizeWithConstraints(
        fs, CFRangeMake(0, 0), nil,
        CGSize(width: width, height: .greatestFiniteMagnitude), nil)
    return ceil(size.height) + leading
}

/// Draw wrapped text into `rect`, returning the height actually used.
@discardableResult
func draw(_ text: String, in rect: CGRect, font f: CTFont,
          color: CGColor, leading: CGFloat, ctx: CGContext) -> CGFloat {
    let style = NSMutableParagraphStyle()
    style.lineSpacing = leading
    style.alignment = .left

    let attrs: [NSAttributedString.Key: Any] = [
        .font: f,
        .foregroundColor: NSColor(cgColor: color) ?? .white,
        .paragraphStyle: style
    ]
    let attributed = NSAttributedString(string: text, attributes: attrs)
    let framesetter = CTFramesetterCreateWithAttributedString(attributed)

    let path = CGPath(rect: rect, transform: nil)
    let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)

    ctx.saveGState()
    ctx.textMatrix = .identity
    CTFrameDraw(frame, ctx)
    ctx.restoreGState()

    let used = CTFramesetterSuggestFrameSizeWithConstraints(
        framesetter, CFRangeMake(0, 0), nil,
        CGSize(width: rect.width, height: .greatestFiniteMagnitude), nil)
    return used.height
}

// MARK: - Compose

func loadImage(_ path: String) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)
    else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

func compose(_ slide: Slide, size: CGSize) -> CGImage? {
    let cs = CGColorSpaceCreateDeviceRGB()
    // No alpha: the store requires flattened RGB.
    guard let ctx = CGContext(data: nil,
                              width: Int(size.width), height: Int(size.height),
                              bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { return nil }

    ctx.interpolationQuality = .high

    // --- ground ---------------------------------------------------------
    let grad = CGGradient(colorsSpace: cs, colors: [bgTop, bgBottom] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(grad,
                           start: CGPoint(x: 0, y: size.height),
                           end: CGPoint(x: 0, y: 0), options: [])

    // A soft wash of the slide's colour, so the four read as a set while
    // still being individually distinguishable in a store listing.
    if let wash = CGGradient(colorsSpace: cs,
                             colors: [slide.tintColor.copy(alpha: 0.20)!,
                                      slide.tintColor.copy(alpha: 0.0)!] as CFArray,
                             locations: [0, 1]) {
        ctx.drawRadialGradient(wash,
                               startCenter: CGPoint(x: size.width * 0.16, y: size.height * 0.80),
                               startRadius: 0,
                               endCenter: CGPoint(x: size.width * 0.16, y: size.height * 0.80),
                               endRadius: size.width * 0.55,
                               options: [])
    }

    let margin = size.width * 0.062
    let textWidth = size.width * 0.36

    // Text flows downward from a single anchor rather than sitting in fixed
    // rects — otherwise a short headline leaves a hole above the subhead.
    var cursor = size.height * 0.80

    // --- accent rule ----------------------------------------------------
    ctx.setFillColor(slide.tintColor)
    ctx.fill(CGRect(x: margin, y: cursor + size.height * 0.045,
                    width: size.width * 0.055, height: size.height * 0.006))

    // --- headline -------------------------------------------------------
    let headSize = size.height * 0.062
    let headFont = font(headSize, weight: .bold)
    let headH = measure(slide.headline, font: headFont,
                        width: textWidth, leading: headSize * 0.14)
    draw(slide.headline,
         in: CGRect(x: margin, y: cursor - headH, width: textWidth, height: headH),
         font: headFont, color: ink, leading: headSize * 0.14, ctx: ctx)
    cursor -= headH + size.height * 0.045

    // --- subhead --------------------------------------------------------
    let subSize = size.height * 0.0225
    let subFont = font(subSize, weight: .regular)
    let subH = measure(slide.subhead, font: subFont,
                       width: textWidth, leading: subSize * 0.42)
    draw(slide.subhead,
         in: CGRect(x: margin, y: cursor - subH, width: textWidth, height: subH),
         font: subFont, color: dim, leading: subSize * 0.42, ctx: ctx)

    // --- the real capture ----------------------------------------------
    guard let shot = loadImage(config.imageDir + "/" + slide.file) else {
        FileHandle.standardError.write(Data("missing capture: \(slide.file)\n".utf8))
        return nil
    }

    let maxW = size.width * 0.50
    let maxH = size.height * 0.78
    let scale = min(maxW / CGFloat(shot.width), maxH / CGFloat(shot.height))
    let w = CGFloat(shot.width) * scale
    let h = CGFloat(shot.height) * scale
    let frame = CGRect(x: size.width - margin - w,
                       y: (size.height - h) / 2,
                       width: w, height: h)

    let radius = size.width * 0.010
    let clip = CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius,
                      transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size.height * 0.012),
                  blur: size.width * 0.022,
                  color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.55))
    ctx.addPath(clip)
    ctx.setFillColor(bgBottom)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(clip)
    ctx.clip()
    ctx.draw(shot, in: frame)
    ctx.restoreGState()

    // Hairline so the capture separates from the ground.
    ctx.saveGState()
    ctx.addPath(clip)
    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.12))
    ctx.setLineWidth(max(size.width * 0.0009, 1))
    ctx.strokePath()
    ctx.restoreGState()

    return ctx.makeImage()
}

func write(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

// MARK: - Run

// Every size the Mac App Store accepts, all 16:10.
let sizes: [(String, CGSize)] = [
    ("2880x1800", CGSize(width: 2880, height: 1800)),
    ("1280x800",  CGSize(width: 1280, height: 800))
]

let root = URL(fileURLWithPath: config.outputDir)
try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

var made = 0
for (label, size) in sizes {
    let dir = root.appendingPathComponent(label)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    var ok = 0
    for (i, slide) in slides.enumerated() {
        guard let img = compose(slide, size: size) else { continue }
        write(img, to: dir.appendingPathComponent(String(format: "%02d.png", i + 1)))
        ok += 1
        made += 1
    }
    // Report what was actually produced. Claiming success while every capture
    // failed to load is worse than failing outright.
    if ok == slides.count {
        print("wrote \(ok) slides at \(label)")
    } else {
        print("wrote \(ok) of \(slides.count) slides at \(label)")
    }
}

if made == 0 {
    let msg = "no images produced — check that imageDir '\(config.imageDir)' exists "
            + "and contains the files named in the config\n"
    FileHandle.standardError.write(Data(msg.utf8))
    exit(1)
}

print("total \(made) images in \(config.outputDir)/")
