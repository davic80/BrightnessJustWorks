#!/usr/bin/env swift
// generate_icons.swift
// Draws the BrightnessJustWorks app icon: blue-indigo gradient background,
// smaller sun (upper-left), accurate macOS arrow cursor (lower-right, tip
// near sun centre) and writes all required AppIcon sizes plus the menu-bar
// template icon (sun + mini cursor, 18/36 px).
//
// Run from the project root:
//   swift generate_icons.swift

import AppKit
import CoreGraphics

// MARK: - Top-level icon composer

func drawIcon(size: CGFloat, forMenuBar: Bool = false) -> NSImage {
    // Draw directly into a CGBitmapContext so the PNG is exactly size×size pixels,
    // regardless of the display's backing scale factor.
    let px = Int(size)
    let space = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: px, height: px,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return NSImage(size: NSSize(width: size, height: size)) }

    if forMenuBar {
        drawMenuBarComposite(ctx: ctx, size: size)
    } else {
        drawBackground(ctx: ctx, size: size)
        let sunSize   = size * 0.55
        let sunCenter = CGPoint(x: size * 0.38, y: size * 0.62)
        drawSun(ctx: ctx, center: sunCenter, size: sunSize, color: .white)
        let cursorSize = size * 0.38
        let cursorTip  = CGPoint(x: size * 0.52, y: size * 0.22)
        drawCursor(ctx: ctx, tip: cursorTip, size: cursorSize)
    }

    guard let cgImage = ctx.makeImage() else { return NSImage(size: NSSize(width: size, height: size)) }
    return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
}

// MARK: - Menu-bar composite (template: white on transparent)

func drawMenuBarComposite(ctx: CGContext, size: CGFloat) {
    // Sun occupies left ~60 % of the strip, cursor the right ~40 %
    let sunSize   = size * 0.80
    let sunCenter = CGPoint(x: size * 0.38, y: size * 0.50)
    drawSun(ctx: ctx, center: sunCenter, size: sunSize, color: .white)

    let cursorSize = size * 0.44
    let cursorTip  = CGPoint(x: size * 0.62, y: size * 0.18)
    drawCursor(ctx: ctx, tip: cursorTip, size: cursorSize)
}

// MARK: - Background

func drawBackground(ctx: CGContext, size: CGFloat) {
    let radius = size * 0.80
    let colors: CFArray = [
        NSColor(calibratedRed: 0.20, green: 0.50, blue: 1.00, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.06, green: 0.15, blue: 0.52, alpha: 1).cgColor
    ] as CFArray
    let locations: [CGFloat] = [0, 1]
    let space = CGColorSpaceCreateDeviceRGB()
    guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: locations) else { return }

    let cornerR = size * 0.22
    let rect    = CGRect(origin: .zero, size: CGSize(width: size, height: size))
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: cornerR, cornerHeight: cornerR, transform: nil))
    ctx.clip()

    ctx.drawRadialGradient(
        gradient,
        startCenter: CGPoint(x: size * 0.38, y: size * 0.62),
        startRadius: 0,
        endCenter:   CGPoint(x: size * 0.38, y: size * 0.62),
        endRadius:   radius,
        options:     [.drawsAfterEndLocation])
}

// MARK: - Sun

func drawSun(ctx: CGContext, center: CGPoint, size: CGFloat, color: NSColor) {
    let coreR    = size * 0.195
    let rayInner = size * 0.260
    let rayOuter = size * 0.420
    let rayWidth = size * 0.070
    let numRays  = 8

    ctx.saveGState()
    ctx.setFillColor(color.cgColor)

    // Core disc
    ctx.fillEllipse(in: CGRect(
        x: center.x - coreR, y: center.y - coreR,
        width: coreR * 2, height: coreR * 2))

    // Rays
    for i in 0..<numRays {
        let angle = CGFloat(i) * (.pi * 2 / CGFloat(numRays))
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: angle)
        let rayRect = CGRect(x: -rayWidth / 2, y: rayInner, width: rayWidth, height: rayOuter - rayInner)
        ctx.addPath(CGPath(
            roundedRect: rayRect,
            cornerWidth: rayWidth / 2,
            cornerHeight: rayWidth / 2,
            transform: nil))
        ctx.fillPath()
        ctx.restoreGState()
    }

    ctx.restoreGState()
}

// MARK: - macOS arrow cursor
// Accurate 7-point polygon matching the real macOS Default cursor shape.
// `tip` is the hotspot (upper-left tip of the arrow) in CGContext coords (y-up).

func drawCursor(ctx: CGContext, tip: CGPoint, size: CGFloat) {
    let w = size
    let h = size * 1.50

    // All points relative to tip which is at the top-left
    let pts: [(CGFloat, CGFloat)] = [
        (0,         0),           // 0 – tip (hotspot)
        (0,         -h),          // 1 – bottom-left of shaft
        (w * 0.28,  -h * 0.60),  // 2 – notch (inner concave)
        (w * 0.48,  -h * 0.97),  // 3 – tail bottom-right
        (w * 0.62,  -h * 0.86),  // 4 – tail top-right
        (w * 0.38,  -h * 0.50),  // 5 – notch (outer)
        (w * 0.68,  -h * 0.50),  // 6 – right shoulder
    ]

    func absolute(_ p: (CGFloat, CGFloat)) -> CGPoint {
        CGPoint(x: tip.x + p.0, y: tip.y + p.1)
    }

    func makePath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: absolute(pts[0]))
        for p in pts.dropFirst() { path.addLine(to: absolute(p)) }
        path.closeSubpath()
        return path
    }

    // Dark drop-shadow pass
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 1.2, height: -2.0),
        blur:   size * 0.10,
        color:  NSColor(white: 0, alpha: 0.50).cgColor)
    ctx.setFillColor(NSColor(white: 0.10, alpha: 1).cgColor)
    ctx.addPath(makePath())
    ctx.fillPath()
    ctx.restoreGState()

    // White fill (on top)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.addPath(makePath())
    ctx.fillPath()
}

// MARK: - PNG writer

func writePNG(_ image: NSImage, to path: String) {
    guard let tiff   = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png    = bitmap.representation(using: .png, properties: [:]) else {
        print("ERROR: could not encode \(path)")
        return
    }
    do {
        try png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    } catch {
        print("ERROR writing \(path): \(error)")
    }
}

// MARK: - Entry point

let assetBase = "BrightCursor/Assets.xcassets"
let iconDir   = "\(assetBase)/AppIcon.appiconset"
let mbDir     = "\(assetBase)/MenuBarIcon.imageset"

let appSizes: [(Int, String)] = [
    (16,   "icon_16x16.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_64x64.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_1024x1024.png"),
]

for (px, name) in appSizes {
    writePNG(drawIcon(size: CGFloat(px)), to: "\(iconDir)/\(name)")
}

writePNG(drawIcon(size: 18, forMenuBar: true), to: "\(mbDir)/menubar.png")
writePNG(drawIcon(size: 36, forMenuBar: true), to: "\(mbDir)/menubar@2x.png")

print("Done.")
