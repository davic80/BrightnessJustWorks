// BrightnessOverlayWindow.swift
// Displays a native macOS-style brightness OSD on whichever screen the cursor
// is on. Mimics the system volume/brightness bezel: dark vibrancy background,
// sun SF Symbol, row of 16 chiclets, auto-dismiss after 2 s with fade.
//
// One NSPanel is created per CGDirectDisplayID and reused on repeat presses.
// All methods must be called on the main actor.

import AppKit
import OSLog

// MARK: - Constants

private let kOverlayWidth: CGFloat = 200
private let kOverlayHeight: CGFloat = 200
private let kCornerRadius: CGFloat = 18
private let kIconSize: CGFloat = 48
private let kChicletCount: Int = 16
private let kChicletHeight: CGFloat = 8
private let kChicletSpacing: CGFloat = 4
private let kFadeDuration: TimeInterval = 0.35
private let kDisplayDuration: TimeInterval = 1.8
private let overlayLogger = Logger(subsystem: "com.bjw.app", category: "BrightnessOverlay")

// MARK: - Overlay content view

/// Dark-vibrancy rounded panel content: icon + chiclet bar.
private final class OverlayContentView: NSView {

    var filledChiclets: Int = 0 {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Background: dark rounded rect
        ctx.setFillColor(NSColor(white: 0.12, alpha: 0.85).cgColor)
        let path = CGPath(
            roundedRect: bounds,
            cornerWidth: kCornerRadius,
            cornerHeight: kCornerRadius,
            transform: nil)
        ctx.addPath(path)
        ctx.fillPath()

        // Sun icon — SF Symbol drawn via NSImage
        let iconConfig = NSImage.SymbolConfiguration(pointSize: kIconSize, weight: .medium)
        if let icon = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(iconConfig) {
            icon.isTemplate = false
            let iconRect = CGRect(
                x: (bounds.width - kIconSize) / 2,
                y: 28,
                width: kIconSize,
                height: kIconSize)
            NSColor.white.setFill()
            icon.draw(in: iconRect)
        }

        // Chiclet bar
        let totalWidth = CGFloat(kChicletCount) * (kChicletHeight + kChicletSpacing) - kChicletSpacing
        let barStartX = (bounds.width - totalWidth) / 2
        let barY = bounds.height - 36

        for index in 0..<kChicletCount {
            let filled = index < filledChiclets
            let color: NSColor = filled
                ? NSColor(white: 1.0, alpha: 1.0)
                : NSColor(white: 1.0, alpha: 0.25)
            ctx.setFillColor(color.cgColor)

            let chicletX = barStartX + CGFloat(index) * (kChicletHeight + kChicletSpacing)
            let chicletRect = CGRect(x: chicletX, y: barY, width: kChicletHeight, height: kChicletHeight)
            let chicletPath = CGPath(
                roundedRect: chicletRect,
                cornerWidth: 2,
                cornerHeight: 2,
                transform: nil)
            ctx.addPath(chicletPath)
            ctx.fillPath()
        }
    }
}

// MARK: - Overlay controller

@MainActor
final class BrightnessOverlay {

    static let shared = BrightnessOverlay()
    private init() {}

    // One panel + content view per display
    private var panels: [CGDirectDisplayID: NSPanel] = [:]
    private var contentViews: [CGDirectDisplayID: OverlayContentView] = [:]
    private var dismissTimers: [CGDirectDisplayID: Timer] = [:]

    // MARK: - Public

    func show(displayID: CGDirectDisplayID, brightnessPercent: Int) {
        let filled = max(0, min(100, brightnessPercent)) * kChicletCount / 100

        let panel = panel(for: displayID)
        let content = contentViews[displayID]
        content?.filledChiclets = filled

        // Cancel any pending dismiss
        dismissTimers[displayID]?.invalidate()

        // Show with fade-in
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 1
        }

        // Schedule fade-out + close
        let timer = Timer.scheduledTimer(
            withTimeInterval: kDisplayDuration,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dismiss(displayID: displayID)
            }
        }
        dismissTimers[displayID] = timer

        overlayLogger.debug("Overlay shown: display=\(displayID) filled=\(filled)/\(kChicletCount)")
    }

    // MARK: - Private

    private func dismiss(displayID: CGDirectDisplayID) {
        guard let panel = panels[displayID] else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = kFadeDuration
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    private func panel(for displayID: CGDirectDisplayID) -> NSPanel {
        if let existing = panels[displayID] { return existing }

        let panel = NSPanel(
            contentRect: overlayRect(for: displayID),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let content = OverlayContentView(frame: CGRect(origin: .zero,
                                                       size: CGSize(width: kOverlayWidth,
                                                                    height: kOverlayHeight)))
        panel.contentView = content
        panels[displayID] = panel
        contentViews[displayID] = content
        return panel
    }

    /// Returns the overlay rect centred horizontally, ~40 % from top on the given display's screen.
    private func overlayRect(for displayID: CGDirectDisplayID) -> CGRect {
        // Find the NSScreen matching this displayID
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
        } ?? NSScreen.main ?? NSScreen.screens[0]

        let screenFrame = screen.frame
        let overlayX = screenFrame.midX - kOverlayWidth / 2
        // Position ~58 % from the bottom (≈ 42 % from the top) — matches system OSD
        let overlayY = screenFrame.minY + screenFrame.height * 0.58 - kOverlayHeight / 2

        return CGRect(x: overlayX, y: overlayY, width: kOverlayWidth, height: kOverlayHeight)
    }
}
