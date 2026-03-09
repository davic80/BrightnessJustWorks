# Changelog

All notable changes to BrightnessJustWorks are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [1.0.0] — 2026-03-09

### Added

- System-wide interception of the physical brightness keys (F1/F2) via `CGEventTap`
- Display routing: brightness adjustment is sent to whichever display the mouse cursor is currently on
- Built-in display brightness control via `DisplayServicesSetBrightness()` (smooth, native, 1/16-step increments)
- External monitor brightness control via DDC/CI over Thunderbolt/USB-C using `IOAVServiceWriteI2C()` (Apple Silicon)
- Native macOS OSD brightness bezel using `OSDManager` from the private `OSD.framework`, with sun icon and 16-chiclet indicator
- Menu bar presence (`LSUIElement`) — no Dock icon
- Accessibility permission prompt on first launch with automatic polling until granted
- Menu bar menu: version label, "Grant Accessibility Access…" shortcut, Quit
- Minimum deployment target: macOS 12 Monterey
- Swift 6.0, Apple Silicon only

---

<!-- unreleased changes go above this line -->
[1.0.0]: https://github.com/davic80/BrightnessJustWorks/releases/tag/v1.0.0
