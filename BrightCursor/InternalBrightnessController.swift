// InternalBrightnessController.swift
// Controls the brightness of the built-in MacBook display (and Apple external
// displays like Studio Display / Pro Display XDR) using the private
// DisplayServices framework API.
//
// DisplayServicesSetBrightness / DisplayServicesGetBrightness operate on a
// 0.0–1.0 float scale. Each key press steps by 1/16 (6.25%), matching
// macOS native behaviour.

import CoreGraphics
import os.log

private let kStep: Float = 0.0625   // 1 ÷ 16 steps

final class InternalBrightnessController {

    private let logger = Logger(subsystem: "com.bjw.app", category: "InternalBrightness")

    @discardableResult
    func adjustBrightness(displayID: CGDirectDisplayID, increase: Bool) -> Float? {
        var current: Float = 0.5
        let getResult = DisplayServicesGetBrightness(displayID, &current)
        if getResult != 0 {
            logger.error("DisplayServicesGetBrightness failed (\(getResult)) for display \(displayID) — using 0.5")
            current = 0.5
        }

        let delta: Float = increase ? kStep : -kStep
        let newValue = min(1.0, max(0.0, current + delta))

        let setResult = DisplayServicesSetBrightness(displayID, newValue)
        if setResult == 0 {
            logger.info("Internal brightness set to \(newValue, format: .fixed(precision: 3)) on display \(displayID)")
            return newValue
        } else {
            logger.error("DisplayServicesSetBrightness failed (\(setResult)) for display \(displayID)")
            return nil
        }
    }
}
