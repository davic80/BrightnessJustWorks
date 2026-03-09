#!/usr/bin/env swift
// generate_icons.swift
// Draws a sleek sun + macOS arrow cursor composite icon and writes all
// required AppIcon sizes plus the MenuBar icon (18 / 36 px @1x/@2x).
//
// Run from the project root:
//   swift generate_icons.swift

import AppKit
import CoreGraphics

// MARK: - Drawing helpers

func drawIcon(size: CGFloat, forMenuBar: Bool = false) -> NSImage {
    let canvas = NSImage(size: NSSize(width: size, height: size))
    canvas.lockFocus()
    defer { canvas.unlockFocus() }

    guard let ctx = NSGraphicsContext.current?.cgContext else { return canvas }

    if forMenuBar {
        // Menu bar: white template — sun only, no background, no cursor
        let center = CGPoint(x: size / 2, y: size / 2)
        drawSun(ctx: ctx, center: center, size: size, color: .white, menuBar: true)
    } else {
        // App icon: gradient background + sun (upper-left) + cursor (lower-right)
        drawBackground(ctx: ctx, size: size)
        // Sun: centred slightly upper-left
        let sunCenter = CGPoint(x: size * 0.42, y: size * 0.56)
        let sunSize = size * 0.72
        drawSun(ctx: ctx, center: sunCenter, size: sunSize, color: .white, menuBar: false)
        // Cursor: smaller, lower-right, tip near sun centre
        let cursorSize = size * 0.28
        let cursorTip = CGPoint(x: size * 0.54, y: size * 0.28)
        drawCursor(ctx: ctx, tip: cursorTip, size: cursorSize)
    }

    return canvas
}

// MARK: - Background

func drawBackground(ctx: CGContext, size: CGFloat) {
    // Deep blue-to-indigo radial gradient — macOS-ish feel
    let radius = size * 0.72
    let colors = [
        NSColor(calibratedRed: 0.18, green: 0.48, blue: 0.98, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.08, green: 0.18, blue: 0.55, alpha: 1).cgColor
    ] as CFArray
    let locations: [CGFloat] = [0, 1]
    let space = CGColorSpaceCreateDeviceRGB()
    guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: locations) else { return }

    let cornerR = size * 0.22
    let rect = CGRect(origin: .zero, size: CGSize(width: size, height: size))
    let bgPath = CGPath(roundedRect: rect, cornerWidth: cornerR, cornerHeight: cornerR, transform: nil)
    ctx.addPath(bgPath)
    ctx.clip()

    ctx.drawRadialGradient(
        gradient,
        startCenter: CGPoint(x: size * 0.42, y: size * 0.58),
        startRadius: 0,
        endCenter: CGPoint(x: size * 0.42, y: size * 0.58),
        endRadius: radius,
        options: [.drawsAfterEndLocation])
}

// MARK: - Sun

func drawSun(ctx: CGContext, center: CGPoint, size: CGFloat, color: NSColor, menuBar: Bool) {
    let coreR = size * (menuBar ? 0.22 : 0.20)
    let rayInner = size * (menuBar ? 0.28 : 0.27)
    let rayOuter = size * (menuBar ? 0.44 : 0.43)
    let rayWidth = size * (menuBar ? 0.07 : 0.065)
    let numRays = 8

    ctx.saveGState()
    ctx.setFillColor(color.cgColor)
    ctx.setStrokeColor(color.cgColor)

    // Core circle
    let coreRect = CGRect(x: center.x - coreR, y: center.y - coreR, width: coreR * 2, height: coreR * 2)
    ctx.fillEllipse(in: coreRect)

    // Rays — rounded rectangles rotated around center
    for i in 0..<numRays {
        let angle = CGFloat(i) * (.pi * 2 / CGFloat(numRays))
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: angle)
        let rayRect = CGRect(
            x: -rayWidth / 2,
            y: rayInner,
            width: rayWidth,
            height: rayOuter - rayInner)
        let rayPath = CGPath(
            roundedRect: rayRect,
            cornerWidth: rayWidth / 2,
            cornerHeight: rayWidth / 2,
            transform: nil)
        ctx.addPath(rayPath)
        ctx.fillPath()
        ctx.restoreGState()
    }

    ctx.restoreGState()
}

// MARK: - macOS arrow cursor

func drawCursor(ctx: CGContext, tip: CGPoint, size: CGFloat) {
    // Classic macOS arrow cursor: white fill + dark outline for legibility
    // The arrow points up-left. tip is the hotspot of the arrow.
    let w = size
    let h = size * 1.55

    // Arrow polygon (tip at top, pointing up-left)
    // Points defined relative to tip
    let tipX = tip.x
    let tipY = tip.y + h          // tip is at top in macOS coords (y up)

    let points: [(CGFloat, CGFloat)] = [
        (tipX, tipY),                             // tip
        (tipX, tipY - h),                         // bottom-left
        (tipX + w * 0.30, tipY - h * 0.62),      // notch inner
        (tipX + w * 0.52, tipY - h * 0.98),      // tail right bottom
        (tipX + w * 0.65, tipY - h * 0.88),      // tail right top
        (tipX + w * 0.42, tipY - h * 0.52),      // notch outer
        (tipX + w * 0.72, tipY - h * 0.52),      // right shoulder
    ]

    func makePath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: points[0].0, y: points[0].1))
        for pt in points.dropFirst() {
            path.addLine(to: CGPoint(x: pt.0, y: pt.1))
        }
        path.closeSubpath()
        return path
    }

    // Shadow / dark outline (drawn slightly larger)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 1, height: -2), blur: size * 0.08,
                  color: NSColor(white: 0, alpha: 0.45).cgColor)
    ctx.setFillColor(NSColor(white: 0.12, alpha: 1).cgColor)
    ctx.addPath(makePath())
    ctx.fillPath()
    ctx.restoreGState()

    // White fill
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.addPath(makePath())
    ctx.fillPath()
}

// MARK: - PNG export

func writePNG(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        print("ERROR: failed to encode \(path)")
        return
    }
    do {
        try png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    } catch {
        print("ERROR writing \(path): \(error)")
    }
}

// MARK: - Main

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
    let img = drawIcon(size: CGFloat(px))
    writePNG(img, to: "\(iconDir)/\(name)")
}

// Menu bar: 18 px (@1x) and 36 px (@2x) — template image (white on transparent)
let mb1x = drawIcon(size: 18, forMenuBar: true)
let mb2x = drawIcon(size: 36, forMenuBar: true)
writePNG(mb1x, to: "\(mbDir)/menubar.png")
writePNG(mb2x, to: "\(mbDir)/menubar@2x.png")

print("Done.")
