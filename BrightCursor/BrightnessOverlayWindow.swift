// BrightnessOverlayWindow.swift
// Displays a native macOS-style brightness OSD on whichever screen the cursor
// is on. Dark rounded panel in the top-right corner, SF Symbol sun icon,
// single continuous pill progress bar with a smooth CoreAnimation fill
// transition, auto-dismiss after 2 s with fade.
//
// Flash-free: the panel stays fully visible while the user is pressing keys.
// The fade-in only runs when the panel was previously hidden. The dismiss
// timer is simply rescheduled on every key press.
//
// One NSPanel is created per CGDirectDisplayID and reused on repeat presses.
// All methods must be called on the main actor.

import AppKit
import OSLog
import QuartzCore

// MARK: - Constants

private let kOverlayWidth: CGFloat = 220
private let kOverlayHeight: CGFloat = 56
private let kCornerRadius: CGFloat = 14
private let kIconSize: CGFloat = 20
private let kBarHeight: CGFloat = 6
private let kBarCorner: CGFloat = 3
private let kHorizPadding: CGFloat = 16
private let kTopMargin: CGFloat = 12          // inset from menu-bar bottom
private let kRightMargin: CGFloat = 12        // inset from screen right edge
private let kFadeInDuration: TimeInterval = 0.18
private let kFadeOutDuration: TimeInterval = 0.40
private let kDisplayDuration: TimeInterval = 1.8
private let kFillAnimation: CFTimeInterval = 0.20
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

        trackLayer.backgroundColor = NSColor(white: 1, alpha: 0.22).cgColor
        trackLayer.cornerRadius    = kBarCorner
        trackLayer.masksToBounds   = true
        trackLayer.frame           = root.bounds
        root.addSublayer(trackLayer)

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
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fillLayer.position = CGPoint(x: 0, y: root.bounds.midY)
        fillLayer.bounds = CGRect(x: 0, y: 0, width: root.bounds.width * progress, height: root.bounds.height)
        CATransaction.commit()
    }

    private func animateFill(to newProgress: CGFloat) {
        guard let root = layer else { return }
        let targetWidth = root.bounds.width * newProgress
        let currentWidth = fillLayer.presentation()?.bounds.width ?? fillLayer.bounds.width

        let anim            = CABasicAnimation(keyPath: "bounds.size.width")
        anim.fromValue      = currentWidth
        anim.toValue        = targetWidth
        anim.duration       = kFillAnimation
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
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

/// Dark rounded pill: sun icon (left) + animated pill progress bar (right).
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

        // Sun icon — left-centre
        let iconY = (kOverlayHeight - kIconSize) / 2
        let iconView = NSImageView(frame: CGRect(x: kHorizPadding, y: iconY, width: kIconSize, height: kIconSize))
        let cfg = NSImage.SymbolConfiguration(pointSize: kIconSize * 0.80, weight: .semibold)
        iconView.image = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg)
        iconView.contentTintColor = .white
        iconView.imageScaling     = .scaleProportionallyUpOrDown
        addSubview(iconView)

        // Pill bar — fills remaining width
        let barX = kHorizPadding + kIconSize + kHorizPadding * 0.65
        let barW = kOverlayWidth - barX - kHorizPadding
        let barY = (kOverlayHeight - kBarHeight) / 2
        pillView = PillProgressView(frame: CGRect(x: barX, y: barY, width: barW, height: kBarHeight))
        addSubview(pillView)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(NSColor(white: 0.10, alpha: 0.90).cgColor)
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

    private var panels: [CGDirectDisplayID: NSPanel]              = [:]
    private var contentViews: [CGDirectDisplayID: OverlayContentView] = [:]
    private var dismissTimers: [CGDirectDisplayID: Timer]         = [:]
    // Track whether each panel is currently visible to avoid the fade-in flash
    private var isVisible: [CGDirectDisplayID: Bool]              = [:]

    // MARK: - Public

    func show(displayID: CGDirectDisplayID, brightnessPercent: Int) {
        let fraction = CGFloat(max(0, min(100, brightnessPercent))) / 100.0

        let panel = panel(for: displayID)

        // Always recompute position — handles display layout changes and
        // the cursor moving from one screen to another between presses.
        panel.setFrame(overlayRect(for: displayID), display: false)

        // Update the bar — animates smoothly via CABasicAnimation
        contentViews[displayID]?.brightnessFraction = fraction

        // Reschedule dismiss timer (extends display time while keys are held)
        dismissTimers[displayID]?.invalidate()
        let timer = Timer.scheduledTimer(
            withTimeInterval: kDisplayDuration,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dismiss(displayID: displayID)
            }
        }
        dismissTimers[displayID] = timer

        // Only fade in if the panel is not already visible — prevents the flash
        guard isVisible[displayID] != true else { return }

        isVisible[displayID] = true
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = kFadeInDuration
            panel.animator().alphaValue = 1
        }

        overlayLogger.debug("Overlay shown: display=\(displayID) brightness=\(brightnessPercent)%")
    }

    // MARK: - Private

    private func dismiss(displayID: CGDirectDisplayID) {
        guard let panel = panels[displayID] else { return }
        isVisible[displayID] = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = kFadeOutDuration
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        })
    }

    private func panel(for displayID: CGDirectDisplayID) -> NSPanel {
        if let existing = panels[displayID] { return existing }

        let panel = NSPanel(
            contentRect: overlayRect(for: displayID),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.level              = .screenSaver
        panel.backgroundColor    = .clear
        panel.isOpaque           = false
        panel.hasShadow          = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let content = OverlayContentView(frame: CGRect(
            origin: .zero,
            size: CGSize(width: kOverlayWidth, height: kOverlayHeight)))
        panel.contentView       = content
        panels[displayID]       = panel
        contentViews[displayID] = content
        return panel
    }

    /// Top-right corner of the display, just below the menu bar.
    /// Uses visibleFrame (which macOS keeps correct for every screen — it
    /// already excludes the menu bar on whichever display hosts it) so the
    /// overlay is always flush with the top-right regardless of which display
    /// is primary and regardless of display resolution or arrangement.
    private func overlayRect(for displayID: CGDirectDisplayID) -> CGRect {
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
        } ?? NSScreen.main ?? NSScreen.screens[0]

        // visibleFrame.maxY is the bottom edge of the menu bar on this screen.
        // visibleFrame.maxX is the right edge (minus any Dock on the right).
        // We position the overlay in the top-right corner with fixed margins.
        let vf       = screen.visibleFrame
        let overlayX = vf.maxX - kOverlayWidth - kRightMargin
        let overlayY = vf.maxY - kTopMargin - kOverlayHeight

        return CGRect(x: overlayX, y: overlayY, width: kOverlayWidth, height: kOverlayHeight)
    }
}
