// OSDOverlay.swift
// Shows the native macOS brightness OSD bezel (sun icon + chiclet indicator)
// using the private OSD.framework / OSDManager XPC interface.
//
// OSDManager.sharedManager() returns a proxy that forwards calls to
// OSDUIHelper.xpc. Image type 1 = brightness sun icon (Brightness.pdf
// resource in OSDUIHelper.app). Priority 0x1f4 (500) matches system usage.
// Fade delay 2000 ms matches system behaviour.
//
// We use the filledChiclets:totalChiclets:locked: variant because the
// withText: selector is not forwarded by the NSXPCInterface proxy
// (protocol mismatch — confirmed from binary analysis of OSDUIHelper).

import Foundation
import CoreGraphics
import os.log

// Image index for the brightness sun icon inside OSDUIHelper.app
private let kOSDBrightnessImage: Int64 = 1
private let kOSDPriority: UInt32 = 0x1f4       // 500 — matches system default
private let kOSDFadeMs: UInt32 = 2000           // 2 s before fade
private let kOSDTotalChiclets: UInt32 = 16
private let osdLogger = Logger(subsystem: "com.bjw.app", category: "OSDOverlay")

@MainActor
final class OSDOverlay {

    static let shared = OSDOverlay()
    private init() {}

    /// Show the brightness OSD on the given display.
    /// - Parameters:
    ///   - displayID:         The CGDirectDisplayID to show the OSD on.
    ///   - brightnessPercent: 0–100 integer percentage to display.
    func show(displayID: CGDirectDisplayID, brightnessPercent: Int) {
        guard let manager = OSDManager.sharedManager() as? OSDManager else {
            osdLogger.error("OSDOverlay: failed to get OSDManager.sharedManager()")
            return
        }

        // Map 0–100 % to 0–16 chiclets
        let filled = UInt32(max(0, min(100, brightnessPercent)) * Int(kOSDTotalChiclets) / 100)

        manager.showImage(
            kOSDBrightnessImage,
            onDisplayID: displayID,
            priority: kOSDPriority,
            msecUntilFade: kOSDFadeMs,
            filledChiclets: filled,
            totalChiclets: kOSDTotalChiclets,
            locked: false)

        let chicletInfo = "\(filled)/\(kOSDTotalChiclets)"
        // swiftlint:disable:next line_length
        osdLogger.debug("OSDOverlay: brightness \(brightnessPercent)% (\(chicletInfo) chiclets) on display \(displayID)")
    }
}
