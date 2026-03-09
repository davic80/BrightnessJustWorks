// DisplayRouter.swift
// Determines which display the mouse cursor is currently on and delegates
// brightness adjustment to the appropriate controller (internal vs external).

import AppKit
import CoreGraphics
import os.log

@MainActor
final class DisplayRouter {

    static let shared = DisplayRouter()

    private let log = OSLog(subsystem: "com.bjw.app", category: "DisplayRouter")
    private let internalController = InternalBrightnessController()
    private let externalController = ExternalBrightnessController()

    private init() {
        // Pre-cache the external display service map on a background thread.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.externalController.buildServiceMap()
        }

        // Rebuild the map whenever display configuration changes.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.global(qos: .userInitiated).async {
                self?.externalController.buildServiceMap()
            }
        }
    }

    // MARK: - Public

    /// Called by BrightnessKeyInterceptor on every brightness key press.
    func adjustBrightness(increase: Bool) {
        guard let (displayID, screenName) = displayUnderCursor() else {
            os_log("Could not determine display under cursor.", log: log, type: .error)
            return
        }

        let isBuiltin = CGDisplayIsBuiltin(displayID) != 0
        os_log("Key press: display=%u (%{public}@) builtin=%d increase=%d",
               log: log, type: .default, displayID, screenName, isBuiltin ? 1 : 0, increase ? 1 : 0)

        if isBuiltin {
            if let newValue = internalController.adjustBrightness(displayID: displayID, increase: increase) {
                let percent = Int((newValue * 100).rounded())
                OSDOverlay.shared.show(displayID: displayID,
                                       brightnessPercent: percent)
            }
        } else {
            if let newValue = externalController.adjustBrightness(displayID: displayID, increase: increase) {
                OSDOverlay.shared.show(displayID: displayID,
                                       brightnessPercent: newValue)
            }
        }
    }

    // MARK: - Private

    /// Returns the CGDirectDisplayID and localized name of the screen the mouse cursor is on.
    private func displayUnderCursor() -> (CGDirectDisplayID, String)? {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) else {
            os_log("No screen found for cursor at (%.0f, %.0f) — screens: %{public}@",
                   log: log, type: .error,
                   mouseLocation.x, mouseLocation.y,
                   NSScreen.screens.map { "\($0.localizedName):\($0.frame)" }.joined(separator: ", "))
            return nil
        }
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return nil
        }
        os_log("Cursor at (%.0f, %.0f) → display %u (%{public}@)",
               log: log, type: .default,
               mouseLocation.x, mouseLocation.y, displayID, screen.localizedName)
        return (displayID, screen.localizedName)
    }
}
