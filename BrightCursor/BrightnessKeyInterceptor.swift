// BrightnessKeyInterceptor.swift
// Intercepts MacBook hardware brightness keys via CGEventTap.
//
// Brightness keys arrive as NSEventTypeSystemDefined events (raw value 14).
// They are NOT regular kCGEventKeyDown events — a plain keyDown tap misses them.
//
// Key codes (from IOKit/hidsystem/ev_keymap.h):
//   NX_KEYTYPE_BRIGHTNESS_UP   = 2
//   NX_KEYTYPE_BRIGHTNESS_DOWN = 3
//
// data1 field layout:
//   bits 16-23 : key code
//   bits  8-15 : key flags (0x0A = key down, 0x0B = key up)

import AppKit
import CoreGraphics
import os.log

// NX_SYSDEFINED = 14 (from IOKit/hidsystem/IOLLEvent.h)
private let kNXSystemDefined: UInt32 = 14
// NX_KEYTYPE brightness constants
private let kBrightnessUp:   Int32 = 2
private let kBrightnessDown: Int32 = 3
// Key-down flag in data1 bits 8-15
private let kKeyDownFlags: Int = 0x0A00

final class BrightnessKeyInterceptor {

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let log = OSLog(subsystem: "com.bjw.app", category: "KeyInterceptor")

    // MARK: - Start / Stop

    func start() {
        // Tap NSEventTypeSystemDefined (raw 14 = 1 << 14)
        let eventMask = CGEventMask(1 << kNXSystemDefined)

        // Retain self so the C callback can reach us
        let selfPtr = Unmanaged.passRetained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passRetained(event) }
                let me = Unmanaged<BrightnessKeyInterceptor>.fromOpaque(refcon).takeUnretainedValue()
                return me.handle(type: type, event: event)
            },
            userInfo: selfPtr
        ) else {
            os_log("CGEventTapCreate failed — check Accessibility permission.", log: log, type: .error)
            Unmanaged<BrightnessKeyInterceptor>.fromOpaque(selfPtr).release()
            return
        }

        self.eventTap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        os_log("Brightness key interceptor started.", log: log, type: .info)
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    // MARK: - Event Callback

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Tap was disabled by macOS timeout — re-enable it
        if type.rawValue == CGEventType.tapDisabledByTimeout.rawValue ||
           type.rawValue == CGEventType.tapDisabledByUserInput.rawValue {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passRetained(event)
        }

        // Only interested in NSEventTypeSystemDefined (raw = 14)
        guard type.rawValue == kNXSystemDefined else {
            return Unmanaged.passRetained(event)
        }

        // Decode via NSEvent for easy field access
        guard let nsEvent = NSEvent(cgEvent: event) else {
            return Unmanaged.passRetained(event)
        }
        // Confirm subtype == 8 (media/brightness key subtype)
        guard nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passRetained(event)
        }

        let data1  = nsEvent.data1            // NSInteger, always valid
        let keyCode  = Int32((data1 & 0xFFFF0000) >> 16)
        let keyFlags = data1 & 0x0000FFFF

        // Only act on key-down (flags 0x0A00); let key-up through but consume it
        let isKeyDown = (keyFlags & 0xFF00) == kKeyDownFlags

        switch keyCode {
        case kBrightnessUp:
            if isKeyDown {
                os_log("Brightness UP", log: log, type: .debug)
                DispatchQueue.main.async { DisplayRouter.shared.adjustBrightness(increase: true) }
            }
            return nil   // consume both up and down events
        case kBrightnessDown:
            if isKeyDown {
                os_log("Brightness DOWN", log: log, type: .debug)
                DispatchQueue.main.async { DisplayRouter.shared.adjustBrightness(increase: false) }
            }
            return nil
        default:
            return Unmanaged.passRetained(event)
        }
    }
}
