# Changelog

All notable changes to BrightnessJustWorks are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [Unreleased]

### Added

- Native `NSPanel` brightness OSD overlay replacing the private `OSDManager` XPC interface
- OSD positioned in the top-right corner of the active display, just below the menu bar
- Smooth `CABasicAnimation` pill progress bar (easeOut, 0.20 s) replaces 16 discrete chiclets
- Flash-free display: panel stays visible while keys are held; fade-in only triggers when panel was hidden
- Redesigned app icon: smaller sun (55 % of canvas), accurate 7-point macOS arrow cursor (38 %), deep blue-indigo radial gradient background
- Redesigned menu-bar template icon: sun + cursor composite at 18/36 px
- `generate_icons.swift` script draws into `CGBitmapContext` so all PNG assets are exactly the right pixel dimensions (fixes Xcode asset-catalog size warnings)

### Changed

- OSD fade-in reduced to 0.18 s; fade-out extended to 0.40 s for a more natural feel
- Overlay size changed from 200×200 pt square to a compact 220×56 pt pill

### Removed

- Dependency on `OSD.framework` private XPC interface (`OSDManager`)

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
[Unreleased]: https://github.com/davic80/BrightnessJustWorks/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/davic80/BrightnessJustWorks/releases/tag/v1.0.0
