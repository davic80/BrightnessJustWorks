// DisplayRouter.swift
// Determines which display the mouse cursor is currently on and delegates
// brightness adjustment to the appropriate controller (internal vs external).

import AppKit
import CoreGraphics
import OSLog

@MainActor
final class DisplayRouter {

    static let shared = DisplayRouter()

    private let logger = Logger(subsystem: "com.bjw.app", category: "DisplayRouter")
    private let internalController = InternalBrightnessController()
    private let externalController = ExternalBrightnessController()

    private init() {
        // Pre-cache the external display service map on a background thread.
        let ext = externalController
        Task.detached(priority: .userInitiated) {
            ext.buildServiceMap()
        }

        // Rebuild the map whenever display configuration changes.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let ext = self.externalController
            Task.detached(priority: .userInitiated) {
                ext.buildServiceMap()
            }
        }
    }

    // MARK: - Public

    /// Called by BrightnessKeyInterceptor on every brightness key press.
    func adjustBrightness(increase: Bool) {
        guard let (displayID, screenName) = displayUnderCursor() else {
            logger.error("Could not determine display under cursor.")
            return
        }

        let isBuiltin = CGDisplayIsBuiltin(displayID) != 0
        logger.debug("Key press: display=\(displayID) (\(screenName)) builtin=\(isBuiltin) increase=\(increase)")

        if isBuiltin {
            if let newValue = internalController.adjustBrightness(displayID: displayID, increase: increase) {
                let percent = Int((newValue * 100).rounded())
                BrightnessOverlay.shared.show(displayID: displayID, brightnessPercent: percent)
            }
        } else {
            if let newValue = externalController.adjustBrightness(displayID: displayID, increase: increase) {
                BrightnessOverlay.shared.show(displayID: displayID, brightnessPercent: newValue)
            }
        }
    }

    // MARK: - Private

    /// Returns the CGDirectDisplayID and localized name of the screen the mouse cursor is on.
    private func displayUnderCursor() -> (CGDirectDisplayID, String)? {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) else {
            let screenList = NSScreen.screens
                .map { "\($0.localizedName):\($0.frame)" }
                .joined(separator: ", ")
            let pos = "(\(mouseLocation.x), \(mouseLocation.y))"
            logger.error("No screen found for cursor at \(pos) — screens: \(screenList)")
            return nil
        }
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
            as? CGDirectDisplayID else {
            return nil
        }
        let pos = "(\(mouseLocation.x), \(mouseLocation.y))"
        logger.debug("Cursor at \(pos) → display \(displayID) (\(screen.localizedName))")
        return (displayID, screen.localizedName)
    }
}
