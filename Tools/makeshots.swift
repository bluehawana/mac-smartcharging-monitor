#!/usr/bin/env swift
//
// Mac App Store screenshot generator.
//
//   swift makeshots.swift screenshots.json
//   swift makeshots.swift --layouts        # list available layouts
//
// The Mac App Store wants 16:10 landscape at one of 1280x800, 1440x900,
// 2560x1600 or 2880x1800, flattened RGB with no alpha. We render the largest
// and downscale, so one pass covers every accepted size.
//
// Apple requires the image to show the real interface, so these composite
// actual captures. Only the words around them are added.

import Foundation
import AppKit
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

// MARK: - Layouts

/// Each layout answers a different job. Choosing the right one per slide is
/// most of what separates a professional listing from a homemade one, which
/// is why they are named for their purpose rather than their geometry.
enum Layout: String, Decodable, CaseIterable {
    case heroLeft = "hero-left"
    case heroRight = "hero-right"
    case centered
    case showcase
    case spotlight

    var summary: String {
        switch self {
        case .heroLeft:  return "text left, app right — the workhorse, best for slide one"
        case .heroRight: return "mirrored; alternate with hero-left so a set feels composed"
        case .centered:  return "headline centred above the app; when the UI is the argument"
        case .showcase:  return "app nearly full-bleed with a caption; for dense interfaces"
        case .spotlight: return "one huge number beside the app; for a metric worth shouting"
        }
    }
}

// MARK: - Config

struct Slide: Decodable {
    let file: String
    let headline: String
    let subhead: String
    let tint: [Double]
    let layout: Layout?
    /// Only used by `spotlight`. Keep it short: "140 W", "3×", "0 ms".
    let stat: String?

    var tintColor: CGColor {
        CGColor(srgbRed: tint.count > 0 ? tint[0] : 0.31,
                green:   tint.count > 1 ? tint[1] : 0.76,
                blue:    tint.count > 2 ? tint[2] : 0.85, alpha: 1)
    }
    var resolvedLayout: Layout { layout ?? .heroLeft }
}

struct Theme: Decodable {
    let background: [Double]?
    let ink: [Double]?
    let dim: [Double]?

    static func color(_ c: [Double]?, _ fallback: CGColor) -> CGColor {
        guard let c, c.count >= 3 else { return fallback }
        return CGColor(srgbRed: c[0], green: c[1], blue: c[2], alpha: 1)
    }
}

struct ShotConfig: Decodable {
    let imageDir: String
    let outputDir: String
    let theme: Theme?
    let slides: [Slide]
}

// MARK: - Palette

let defaultBg  = CGColor(srgbRed: 0.075, green: 0.098, blue: 0.098, alpha: 1)
let defaultInk = CGColor(srgbRed: 0.965, green: 0.980, blue: 0.976, alpha: 1)
let defaultDim = CGColor(srgbRed: 0.58,  green: 0.64,  blue: 0.63,  alpha: 1)

// MARK: - Text

func font(_ size: CGFloat, weight: NSFont.Weight) -> CTFont {
    NSFont.systemFont(ofSize: size, weight: weight) as CTFont
}

func attributed(_ text: String, font f: CTFont, color: CGColor,
                leading: CGFloat, align: NSTextAlignment) -> NSAttributedString {
    let style = NSMutableParagraphStyle()
    style.lineSpacing = leading
    style.alignment = align
    return NSAttributedString(string: text, attributes: [
        .font: f,
        .foregroundColor: NSColor(cgColor: color) ?? .white,
        .paragraphStyle: style
    ])
}

/// Height this text needs at the given width, so blocks stack without
/// leaving a hole when a headline runs short.
func measure(_ text: String, font f: CTFont, width: CGFloat,
             leading: CGFloat, align: NSTextAlignment = .left) -> CGFloat {
    let fs = CTFramesetterCreateWithAttributedString(
        attributed(text, font: f, color: defaultInk, leading: leading, align: align))
    let size = CTFramesetterSuggestFrameSizeWithConstraints(
        fs, CFRangeMake(0, 0), nil,
        CGSize(width: width, height: .greatestFiniteMagnitude), nil)
    return ceil(size.height) + leading
}

func draw(_ text: String, in rect: CGRect, font f: CTFont, color: CGColor,
          leading: CGFloat, align: NSTextAlignment = .left, ctx: CGContext) {
    let fs = CTFramesetterCreateWithAttributedString(
        attributed(text, font: f, color: color, leading: leading, align: align))
    let frame = CTFramesetterCreateFrame(
        fs, CFRangeMake(0, 0), CGPath(rect: rect, transform: nil), nil)
    ctx.saveGState()
    ctx.textMatrix = .identity
    CTFrameDraw(frame, ctx)
    ctx.restoreGState()
}

// MARK: - Images

func loadImage(_ path: String) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)
    else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

/// Draw a capture inside `box`, scaled to fit, with rounded corners, a shadow
/// and a hairline so it separates from the ground.
func place(_ shot: CGImage, in box: CGRect, size: CGSize,
           ground: CGColor, ctx: CGContext) {
    let scale = min(box.width / CGFloat(shot.width), box.height / CGFloat(shot.height))
    let w = CGFloat(shot.width) * scale
    let h = CGFloat(shot.height) * scale
    let frame = CGRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h)

    let radius = size.width * 0.010
    let clip = CGPath(roundedRect: frame, cornerWidth: radius,
                      cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size.height * 0.012),
                  blur: size.width * 0.022,
                  color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.55))
    ctx.addPath(clip)
    ctx.setFillColor(ground)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(clip)
    ctx.clip()
    ctx.draw(shot, in: frame)
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(clip)
    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.12))
    ctx.setLineWidth(max(size.width * 0.0009, 1))
    ctx.strokePath()
    ctx.restoreGState()
}


// MARK: - Capture

/// Grab a running app's window straight to a PNG.
///
/// This needs Screen Recording permission, which belongs to the *terminal*
/// running the script rather than to the script itself. Without it macOS
/// returns a desktop-only image with no windows, so we detect that and say
/// so rather than writing a useless file.
enum Capture {

    /// Window IDs belonging to `appName`, largest first — the main window is
    /// almost always the biggest one on screen.
    static func windowIDs(forApp appName: String) -> [(id: CGWindowID, area: CGFloat, title: String)] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return [] }

        var found: [(CGWindowID, CGFloat, String)] = []
        for w in list {
            guard let owner = w[kCGWindowOwnerName as String] as? String,
                  owner.localizedCaseInsensitiveContains(appName),
                  let id = w[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = w[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? CGFloat,
                  let height = bounds["Height"] as? CGFloat
            else { continue }
            // Skip menu bar items and other chrome.
            if width < 200 || height < 150 { continue }
            let title = (w[kCGWindowName as String] as? String) ?? ""
            found.append((id, width * height, title))
        }
        return found.sorted { $0.1 > $1.1 }
    }

    /// Every window the capture API will admit to, regardless of owner.
    /// Empty means no Screen Recording permission — there is always at least
    /// one window on a running Mac.
    static func allWindows() -> [[String: Any]] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        return (CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]) ?? []
    }

    static func isRunning(_ appName: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            ($0.localizedName ?? "").localizedCaseInsensitiveContains(appName)
                || ($0.bundleIdentifier ?? "").localizedCaseInsensitiveContains(appName)
        }
    }

    @discardableResult
    static func window(ofApp appName: String, to path: String) -> Bool {
        let windows = windowIDs(forApp: appName)
        guard let target = windows.first else {
            // Three different failures look identical from here, so separate
            // them: an app that is not running, an app running without a
            // visible window (common for menu bar apps), and a terminal
            // without Screen Recording permission.
            let anyVisible = !allWindows().isEmpty
            let msg: String

            if !anyVisible {
                msg = """
                    cannot see any windows at all.

                    This terminal is missing Screen Recording permission —
                    without it macOS hides every window from the capture API.

                    System Settings > Privacy & Security > Screen Recording,
                    add your terminal, then restart it.

                    """
            } else if isRunning(appName) {
                msg = """
                    "\(appName)" is running but has no visible window.

                    Menu bar apps commonly sit with no window open. Open the
                    window you want to capture first — for a menu bar app,
                    click its icon and choose whatever opens a window.

                    """
            } else {
                msg = """
                    no running app matches "\(appName)".

                    Check the name with:  swift makeshots.swift --windows <name>
                    Partial names work, and matching is case-insensitive.

                    """
            }
            FileHandle.standardError.write(Data(msg.utf8))
            return false
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -l<id> a specific window, -o without shadow, -x silently.
        proc.arguments = ["-l\(target.id)", "-o", "-x", path]
        do { try proc.run() } catch {
            FileHandle.standardError.write(Data("could not run screencapture\n".utf8))
            return false
        }
        proc.waitUntilExit()

        guard proc.terminationStatus == 0,
              FileManager.default.fileExists(atPath: path) else {
            FileHandle.standardError.write(Data("screencapture failed\n".utf8))
            return false
        }
        let label = target.title.isEmpty ? "window \(target.id)" : "\"\(target.title)\""
        print("captured \(label) -> \(path)")
        return true
    }
}

// MARK: - Compose

func compose(_ slide: Slide, size: CGSize, config: ShotConfig) -> CGImage? {
    let cs = CGColorSpaceCreateDeviceRGB()
    // No alpha — the store rejects images carrying an alpha channel.
    guard let ctx = CGContext(data: nil,
                              width: Int(size.width), height: Int(size.height),
                              bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { return nil }
    ctx.interpolationQuality = .high

    let bg  = Theme.color(config.theme?.background, defaultBg)
    let ink = Theme.color(config.theme?.ink, defaultInk)
    let dim = Theme.color(config.theme?.dim, defaultDim)

    guard let shot = loadImage(config.imageDir + "/" + slide.file) else {
        FileHandle.standardError.write(Data("missing capture: \(slide.file)\n".utf8))
        return nil
    }

    // --- ground ---------------------------------------------------------
    var darker = bg.components ?? [0.075, 0.098, 0.098, 1]
    for i in 0..<min(3, darker.count) { darker[i] *= 0.6 }
    let bgBottom = CGColor(srgbRed: darker[0], green: darker[1], blue: darker[2], alpha: 1)

    if let grad = CGGradient(colorsSpace: cs, colors: [bg, bgBottom] as CFArray,
                             locations: [0, 1]) {
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: size.height),
                               end: CGPoint(x: 0, y: 0), options: [])
    }

    // Tint wash sits behind the text side of whichever layout is in use, so a
    // set reads as one family while staying individually distinguishable.
    let washX: CGFloat
    switch slide.resolvedLayout {
    case .heroRight:           washX = 0.84
    case .centered, .showcase: washX = 0.50
    default:                   washX = 0.16
    }
    if let wash = CGGradient(colorsSpace: cs,
                             colors: [slide.tintColor.copy(alpha: 0.20)!,
                                      slide.tintColor.copy(alpha: 0.0)!] as CFArray,
                             locations: [0, 1]) {
        let c = CGPoint(x: size.width * washX, y: size.height * 0.80)
        ctx.drawRadialGradient(wash, startCenter: c, startRadius: 0,
                               endCenter: c, endRadius: size.width * 0.55, options: [])
    }

    let margin = size.width * 0.062

    /// Headline + subhead flowing down from `top`, used by the hero layouts.
    func textStack(x: CGFloat, width: CGFloat, top: CGFloat,
                   align: NSTextAlignment, rule: Bool) {
        var cursor = top

        if rule {
            let ruleW = size.width * 0.055
            let ruleX = align == .center ? x + (width - ruleW) / 2 : x
            ctx.setFillColor(slide.tintColor)
            ctx.fill(CGRect(x: ruleX, y: cursor + size.height * 0.045,
                            width: ruleW, height: size.height * 0.006))
        }

        let headSize = size.height * 0.062
        let headFont = font(headSize, weight: .bold)
        let headH = measure(slide.headline, font: headFont, width: width,
                            leading: headSize * 0.14, align: align)
        draw(slide.headline,
             in: CGRect(x: x, y: cursor - headH, width: width, height: headH),
             font: headFont, color: ink, leading: headSize * 0.14,
             align: align, ctx: ctx)
        cursor -= headH + size.height * 0.045

        let subSize = size.height * 0.0225
        let subFont = font(subSize, weight: .regular)
        let subH = measure(slide.subhead, font: subFont, width: width,
                           leading: subSize * 0.42, align: align)
        draw(slide.subhead,
             in: CGRect(x: x, y: cursor - subH, width: width, height: subH),
             font: subFont, color: dim, leading: subSize * 0.42,
             align: align, ctx: ctx)
    }

    switch slide.resolvedLayout {

    case .heroLeft:
        textStack(x: margin, width: size.width * 0.36,
                  top: size.height * 0.80, align: .left, rule: true)
        place(shot, in: CGRect(x: size.width * 0.48, y: size.height * 0.11,
                               width: size.width * 0.46, height: size.height * 0.78),
              size: size, ground: bgBottom, ctx: ctx)

    case .heroRight:
        textStack(x: size.width - margin - size.width * 0.36, width: size.width * 0.36,
                  top: size.height * 0.80, align: .left, rule: true)
        place(shot, in: CGRect(x: margin, y: size.height * 0.11,
                               width: size.width * 0.46, height: size.height * 0.78),
              size: size, ground: bgBottom, ctx: ctx)

    case .centered:
        textStack(x: size.width * 0.18, width: size.width * 0.64,
                  top: size.height * 0.94, align: .center, rule: false)
        place(shot, in: CGRect(x: size.width * 0.14, y: size.height * 0.05,
                               width: size.width * 0.72, height: size.height * 0.50),
              size: size, ground: bgBottom, ctx: ctx)

    case .showcase:
        place(shot, in: CGRect(x: size.width * 0.10, y: size.height * 0.22,
                               width: size.width * 0.80, height: size.height * 0.72),
              size: size, ground: bgBottom, ctx: ctx)
        let capSize = size.height * 0.036
        let capFont = font(capSize, weight: .semibold)
        let capH = measure(slide.headline, font: capFont, width: size.width * 0.72,
                           leading: capSize * 0.20, align: .center)
        draw(slide.headline,
             in: CGRect(x: size.width * 0.14, y: size.height * 0.15 - capH,
                        width: size.width * 0.72, height: capH),
             font: capFont, color: ink, leading: capSize * 0.20,
             align: .center, ctx: ctx)
        let subSize = size.height * 0.021
        let subFont = font(subSize, weight: .regular)
        let subH = measure(slide.subhead, font: subFont, width: size.width * 0.60,
                           leading: subSize * 0.40, align: .center)
        draw(slide.subhead,
             in: CGRect(x: size.width * 0.20, y: size.height * 0.125 - capH - subH,
                        width: size.width * 0.60, height: subH),
             font: subFont, color: dim, leading: subSize * 0.40,
             align: .center, ctx: ctx)

    case .spotlight:
        // The number carries the slide; headline and subhead support it.
        let colW = size.width * 0.34
        let statText = slide.stat ?? ""
        let statSize = size.height * 0.19
        let statFont = font(statSize, weight: .bold)
        let statH = measure(statText, font: statFont, width: colW, leading: 0)
        draw(statText,
             in: CGRect(x: margin, y: size.height * 0.80 - statH,
                        width: colW, height: statH),
             font: statFont, color: slide.tintColor, leading: 0, ctx: ctx)

        var cursor = size.height * 0.80 - statH - size.height * 0.01

        let headSize = size.height * 0.040
        let headFont = font(headSize, weight: .semibold)
        let headH = measure(slide.headline, font: headFont, width: colW,
                            leading: headSize * 0.16)
        draw(slide.headline,
             in: CGRect(x: margin, y: cursor - headH, width: colW, height: headH),
             font: headFont, color: ink, leading: headSize * 0.16, ctx: ctx)
        cursor -= headH + size.height * 0.030

        let subSize = size.height * 0.021
        let subFont = font(subSize, weight: .regular)
        let subH = measure(slide.subhead, font: subFont, width: colW,
                           leading: subSize * 0.42)
        draw(slide.subhead,
             in: CGRect(x: margin, y: cursor - subH, width: colW, height: subH),
             font: subFont, color: dim, leading: subSize * 0.42, ctx: ctx)

        place(shot, in: CGRect(x: size.width * 0.46, y: size.height * 0.13,
                               width: size.width * 0.48, height: size.height * 0.74),
              size: size, ground: bgBottom, ctx: ctx)
    }

    return ctx.makeImage()
}

func write(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

// MARK: - Run

// --capture <AppName> <out.png>: grab a live window instead of expecting one.
if let i = CommandLine.arguments.firstIndex(of: "--capture") {
    let args = CommandLine.arguments
    guard i + 2 < args.count else {
        FileHandle.standardError.write(Data(
            "usage: --capture <AppName> <output.png>\n".utf8))
        exit(1)
    }
    exit(Capture.window(ofApp: args[i + 1], to: args[i + 2]) ? 0 : 1)
}

if CommandLine.arguments.contains("--windows") {
    let name = CommandLine.arguments.last ?? ""
    let found = Capture.windowIDs(forApp: name)
    if found.isEmpty {
        print("no windows found for \"\(name)\" — is it running, and does this "
            + "terminal have Screen Recording permission?")
    }
    for w in found {
        print("  id \(w.id)  \(Int(w.area)) px²  \(w.title.isEmpty ? "(untitled)" : w.title)")
    }
    exit(0)
}

if CommandLine.arguments.contains("--layouts") {
    print("Layouts:\n")
    for l in Layout.allCases {
        let name = l.rawValue.padding(toLength: 12, withPad: " ", startingAt: 0)
        print("  \(name) \(l.summary)")
    }
    print("\n  spotlight also reads a \"stat\" field, e.g. \"140 W\".")
    exit(0)
}

let configPath = CommandLine.arguments.count > 1 && !CommandLine.arguments[1].hasPrefix("--")
    ? CommandLine.arguments[1] : "screenshots.json"

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
            { "file": "shot.png", "layout": "hero-left",
              "headline": "Big claim", "subhead": "One supporting sentence.",
              "tint": [0.31, 0.76, 0.85] }
          ]
        }

        Run with --layouts to see the available layouts.

        """.utf8))
    exit(1)
}

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
    for (i, slide) in config.slides.enumerated() {
        guard let img = compose(slide, size: size, config: config) else { continue }
        write(img, to: dir.appendingPathComponent(String(format: "%02d.png", i + 1)))
        ok += 1
        made += 1
    }
    // Report what was actually produced. Claiming success while every capture
    // failed to load is worse than failing outright.
    print(ok == config.slides.count
          ? "wrote \(ok) slides at \(label)"
          : "wrote \(ok) of \(config.slides.count) slides at \(label)")
}

if made == 0 {
    let msg = "no images produced — check that imageDir '\(config.imageDir)' exists "
            + "and contains the files named in the config\n"
    FileHandle.standardError.write(Data(msg.utf8))
    exit(1)
}

print("total \(made) images in \(config.outputDir)/")
