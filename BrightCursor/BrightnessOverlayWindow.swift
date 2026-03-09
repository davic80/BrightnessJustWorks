// BrightnessOverlayWindow.swift
// Displays a native macOS-style brightness OSD on whichever screen the cursor
// is on. Dark rounded panel, SF Symbol sun icon, single continuous pill
// progress bar with a smooth CoreAnimation fill transition, auto-dismiss
// after 2 s with fade.
//
// One NSPanel is created per CGDirectDisplayID and reused on repeat presses.
// All methods must be called on the main actor.

import AppKit
import OSLog
import QuartzCore

// MARK: - Constants

private let kOverlayWidth: CGFloat  = 220
private let kOverlayHeight: CGFloat = 100
private let kCornerRadius: CGFloat  = 16
private let kIconSize: CGFloat      = 28
private let kBarHeight: CGFloat     = 8
private let kBarCorner: CGFloat     = 4
private let kHorizPadding: CGFloat  = 20
private let kVertPadding: CGFloat   = 16
private let kFadeDuration: TimeInterval    = 0.35
private let kDisplayDuration: TimeInterval = 1.8
private let kFillAnimation: CFTimeInterval = 0.18
private let overlayLogger = Logger(subsystem: "com.bjw.app", category: "BrightnessOverlay")

// MARK: - Pill progress bar (CALayer-backed)

/// A pill-shaped progress track with a smooth animated fill layer.
private final class PillProgressView: NSView {

    // 0.0 … 1.0
    var progress: CGFloat = 0 {
        didSet { animateFill(to: max(0, min(1, progress))) }
    }

    private let trackLayer = CALayer()
    private let fillLayer  = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setupLayers()
    }

    private func setupLayers() {
        guard let root = layer else { return }

        // Track (dim pill)
        trackLayer.backgroundColor = NSColor(white: 1, alpha: 0.22).cgColor
        trackLayer.cornerRadius    = kBarCorner
        trackLayer.masksToBounds   = true
        trackLayer.frame           = root.bounds
        root.addSublayer(trackLayer)

        // Fill (bright pill, anchored left)
        fillLayer.backgroundColor = NSColor.white.cgColor
        fillLayer.cornerRadius    = kBarCorner
        fillLayer.masksToBounds   = true
        fillLayer.anchorPoint     = CGPoint(x: 0, y: 0.5)
        fillLayer.position        = CGPoint(x: 0, y: root.bounds.midY)
        fillLayer.bounds          = CGRect(x: 0, y: 0, width: 0, height: root.bounds.height)
        root.addSublayer(fillLayer)
    }

    override func layout() {
        super.layout()
        guard let root = layer else { return }
        trackLayer.frame = root.bounds
        // Re-anchor fill without animation after a resize
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fillLayer.position = CGPoint(x: 0, y: root.bounds.midY)
        fillLayer.bounds = CGRect(x: 0, y: 0, width: root.bounds.width * progress, height: root.bounds.height)
        CATransaction.commit()
    }

    private func animateFill(to newProgress: CGFloat) {
        guard let root = layer else { return }
        let targetWidth = root.bounds.width * newProgress

        let anim            = CABasicAnimation(keyPath: "bounds.size.width")
        anim.fromValue      = fillLayer.presentation()?.bounds.width ?? fillLayer.bounds.width
        anim.toValue        = targetWidth
        anim.duration       = kFillAnimation
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        anim.fillMode       = .forwards
        anim.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fillLayer.bounds = CGRect(x: 0, y: 0, width: targetWidth, height: root.bounds.height)
        CATransaction.commit()

        fillLayer.add(anim, forKey: "fillWidth")
    }
}

// MARK: - Overlay content view

/// Dark rounded panel: sun icon (left) + pill progress bar (right).
private final class OverlayContentView: NSView {

    // swiftlint:disable:next implicitly_unwrapped_optional
    private var pillView: PillProgressView!

    var brightnessFraction: CGFloat = 0 {
        didSet { pillView.progress = brightnessFraction }
    }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupSubviews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupSubviews()
    }

    private func setupSubviews() {
        wantsLayer = true

        // Icon sits left-centre
        let iconY = (kOverlayHeight - kIconSize) / 2
        let iconView = NSImageView(frame: CGRect(
            x: kHorizPadding,
            y: iconY,
            width: kIconSize,
            height: kIconSize))
        let cfg = NSImage.SymbolConfiguration(pointSize: kIconSize * 0.72, weight: .medium)
        iconView.image = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg)
        iconView.contentTintColor = .white
        iconView.imageScaling     = .scaleProportionallyUpOrDown
        addSubview(iconView)

        // Pill bar fills the remaining horizontal space
        let barX = kHorizPadding + kIconSize + kHorizPadding * 0.75
        let barW = kOverlayWidth - barX - kHorizPadding
        let barY = (kOverlayHeight - kBarHeight) / 2
        pillView = PillProgressView(frame: CGRect(x: barX, y: barY, width: barW, height: kBarHeight))
        addSubview(pillView)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Background: dark rounded rect with slight translucency
        ctx.setFillColor(NSColor(white: 0.10, alpha: 0.88).cgColor)
        let path = CGPath(
            roundedRect: bounds,
            cornerWidth: kCornerRadius,
            cornerHeight: kCornerRadius,
            transform: nil)
        ctx.addPath(path)
        ctx.fillPath()

        super.draw(dirtyRect)
    }
}

// MARK: - Overlay controller

@MainActor
final class BrightnessOverlay {

    static let shared = BrightnessOverlay()
    private init() {}

    // One panel + content view per display
    private var panels: [CGDirectDisplayID: NSPanel]              = [:]
    private var contentViews: [CGDirectDisplayID: OverlayContentView] = [:]
    private var dismissTimers: [CGDirectDisplayID: Timer]         = [:]

    // MARK: - Public

    func show(displayID: CGDirectDisplayID, brightnessPercent: Int) {
        let fraction = CGFloat(max(0, min(100, brightnessPercent))) / 100.0

        let panel = panel(for: displayID)
        contentViews[displayID]?.brightnessFraction = fraction

        // Cancel any pending dismiss
        dismissTimers[displayID]?.invalidate()

        // Fade in
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 1
        }

        // Schedule fade-out
        let timer = Timer.scheduledTimer(
            withTimeInterval: kDisplayDuration,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dismiss(displayID: displayID)
            }
        }
        dismissTimers[displayID] = timer

        overlayLogger.debug("Overlay shown: display=\(displayID) brightness=\(brightnessPercent)%")
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
        panel.level             = .screenSaver
        panel.backgroundColor   = .clear
        panel.isOpaque          = false
        panel.hasShadow         = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let content = OverlayContentView(frame: CGRect(
            origin: .zero,
            size: CGSize(width: kOverlayWidth, height: kOverlayHeight)))
        panel.contentView = content
        panels[displayID] = panel
        contentViews[displayID] = content
        return panel
    }

    /// Returns the overlay rect centred horizontally, ~42 % from the top of the given display.
    private func overlayRect(for displayID: CGDirectDisplayID) -> CGRect {
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
        } ?? NSScreen.main ?? NSScreen.screens[0]

        let sf       = screen.frame
        let overlayX = sf.midX - kOverlayWidth / 2
        let overlayY = sf.minY + sf.height * 0.58 - kOverlayHeight / 2

        return CGRect(x: overlayX, y: overlayY, width: kOverlayWidth, height: kOverlayHeight)
    }
}
