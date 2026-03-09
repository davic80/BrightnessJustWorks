# BrightnessJustWorks

A macOS menu bar utility that routes the physical brightness keys (F1/F2) to whichever display your mouse cursor is currently on — built-in panel or external monitor.

## The problem

macOS hardwires the brightness keys to the built-in display. If your cursor is on an external monitor, pressing F1/F2 does nothing useful. BrightnessJustWorks intercepts those keys and sends the adjustment to the right screen automatically.

## Features

- Intercepts the system brightness keys system-wide via Accessibility event tap
- Routes brightness up/down to the display under the mouse cursor
- Controls the **built-in display** via `DisplayServices` (smooth, native)
- Controls **external monitors** via DDC/CI over Thunderbolt/USB-C using `IOAVService` (Apple Silicon)
- Shows the native macOS brightness OSD bezel (sun icon + chiclet indicator) on the correct display
- Menu bar only — no Dock icon, no windows
- Step size: ±6.25% (1/16 steps) for internal; ±6 on 0–100 DDC scale for external

## Requirements

- Apple Silicon Mac (M1 / M2 / M3 / M4) — DDC path uses `IOAVService`
- macOS 12 Monterey or later
- Xcode 14 or later (to build from source)
- Accessibility permission (prompted on first launch)

## Building from source

```bash
git clone https://github.com/davic80/BrightnessJustWorks.git
cd BrightnessJustWorks

/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project BrightCursor.xcodeproj \
  -scheme BrightnessJustWorks \
  -configuration Release \
  SYMROOT=/tmp/BJWBuild
```

The built app is at `/tmp/BJWBuild/Release/BrightnessJustWorks.app`.

Copy it to `~/Applications/` (not `/Applications/`) so macOS can grant Accessibility access:

```bash
cp -R /tmp/BJWBuild/Release/BrightnessJustWorks.app ~/Applications/
open ~/Applications/BrightnessJustWorks.app
```

> **Important:** Install to `~/Applications/`, not `/tmp` or the Desktop (iCloud Drive). Apps running from those locations will not appear in System Settings → Privacy & Security → Accessibility.

## First launch

On first launch a system prompt will ask for Accessibility access. Grant it in:

**System Settings → Privacy & Security → Accessibility → BrightnessJustWorks → toggle on**

The app will start working immediately after permission is granted — no restart needed.

## How it works

| Component | What it does |
|---|---|
| `BrightnessKeyInterceptor` | Installs a `CGEventTap` to intercept `NX_KEYTYPE_BRIGHTNESS_UP/DOWN` before the system handles them |
| `DisplayRouter` | Finds the `CGDirectDisplayID` of the screen the mouse cursor is on |
| `InternalBrightnessController` | Calls `DisplayServicesSetBrightness()` for the built-in Retina panel |
| `ExternalBrightnessController` | Sends DDC VCP code `0x10` (brightness) via `IOAVServiceWriteI2C()` |
| `OSDOverlay` | Calls `OSDManager.showImage:onDisplayID:priority:msecUntilFade:filledChiclets:totalChiclets:locked:` to show the native bezel |

## Why not on the Mac App Store

BrightnessJustWorks relies on private Apple APIs (`IOAVService`, `DisplayServices`, `OSDManager`) and requires the Accessibility event tap — neither of which is permitted in the App Store sandbox. It is distributed directly, similar to other display utilities like [MonitorControl](https://github.com/MonitorControl/MonitorControl).

## License

MIT — see [LICENSE](LICENSE).
