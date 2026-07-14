#!/usr/bin/env swift
// Generate AppIcon.iconset/* PNGs from a programmatic drawing of Clawd
// (the Claude Code mascot, chunky welcome-screen variant) on a dark
// squircle. Pass the output directory as the first argument.

import Cocoa

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write("usage: build-icon.swift <output-dir>\n".data(using: .utf8)!)
    exit(1)
}

let outputDir = CommandLine.arguments[1]
let iconsetDir = "\(outputDir)/AppIcon.iconset"

try? FileManager.default.createDirectory(
    atPath: iconsetDir,
    withIntermediateDirectories: true
)

func renderIcon(pixels: Int) -> Data? {
    // Draw into a bitmap directly - NSImage.lockFocus is unreliable
    // outside a running NSApplication.
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    guard let ctx = NSGraphicsContext.current?.cgContext else { return nil }

    let s = CGFloat(pixels)

    // Standard macOS icon grid: the squircle tile occupies ~82.4% of the
    // canvas and the rest is transparent margin. Without the margin the
    // icon renders noticeably larger than neighboring apps.
    let tile = s * 0.824
    let inset = (s - tile) / 2
    let bgRect = NSRect(x: inset, y: inset, width: tile, height: tile)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: tile * 0.225, yRadius: tile * 0.225)
    NSColor(srgbRed: 0.07, green: 0.07, blue: 0.07, alpha: 1).setFill()
    bgPath.fill()

    // Clawd, big pixel variant (from the Claude Code welcome screen):
    //   ` █████████ ` / `██▄█████▄██` (▄ = eye notches) / ` █████████ ` /
    //   `█ █   █ █` legs. Grid: 22 x 16 quadrant units, y measured from top.
    let clawdBody: [(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat)] = [
        (2, 0, 18, 4),                     // head row
        (0, 4, 22, 4),                     // eye row (full width)
        (2, 8, 18, 4),                     // lower body
        (2, 12, 2, 4), (6, 12, 2, 4),      // legs
        (14, 12, 2, 4), (18, 12, 2, 4),
    ]
    let clawdEyes: [(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat)] = [
        (4, 4, 2, 2), (16, 4, 2, 2),       // upper-half eye notches
    ]

    let u = tile * 0.03                    // unit -> 22u = 66% of the tile
    let left = (s - 22 * u) / 2            // tile is centered, so canvas-centering matches
    let top  = (s - 16 * u) / 2            // grid top, measured from icon top
    func fill(_ r: (x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat)) {
        // convert top-down grid coords to CG's bottom-left origin
        ctx.fill(CGRect(x: left + r.x * u,
                        y: s - top - (r.y + r.h) * u,
                        width: r.w * u,
                        height: r.h * u))
    }

    ctx.setFillColor(CGColor(srgbRed: 0.843, green: 0.467, blue: 0.341, alpha: 1)) // #D77757
    clawdBody.forEach(fill)
    ctx.setFillColor(CGColor(srgbRed: 0.07, green: 0.07, blue: 0.07, alpha: 1))    // bg shows through
    clawdEyes.forEach(fill)

    return rep.representation(using: .png, properties: [:])
}

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16.png",      16),
    ("icon_16x16@2x.png",   32),
    ("icon_32x32.png",      32),
    ("icon_32x32@2x.png",   64),
    ("icon_128x128.png",   128),
    ("icon_128x128@2x.png",256),
    ("icon_256x256.png",   256),
    ("icon_256x256@2x.png",512),
    ("icon_512x512.png",   512),
    ("icon_512x512@2x.png",1024),
]

for (name, px) in sizes {
    guard let data = renderIcon(pixels: px) else {
        FileHandle.standardError.write("failed: \(name)\n".data(using: .utf8)!)
        continue
    }
    let url = URL(fileURLWithPath: "\(iconsetDir)/\(name)")
    try? data.write(to: url)
}

print("wrote \(sizes.count) icon variants to \(iconsetDir)")
