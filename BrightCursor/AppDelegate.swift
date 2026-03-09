// AppDelegate.swift
// Sets up the menu bar icon, requests Accessibility permission on first launch,
// and wires together BrightnessKeyInterceptor with DisplayRouter.
// NOTE: No @main attribute — entry point is main.swift.

import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var statusItem: NSStatusItem?
    private var interceptor: BrightnessKeyInterceptor?

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        requestAccessibilityIfNeeded()
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem?.button else { return }

        if let img = NSImage(named: "MenuBarIcon") {
            img.isTemplate = true
            button.image = img
        } else if let img = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: "BrightnessJustWorks") {
            img.isTemplate = true
            button.image = img
        } else {
            button.title = "B"
        }

        let menu = NSMenu()
        let title = NSMenuItem(title: "BrightnessJustWorks 1.0", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Grant Accessibility Access…",
            action: #selector(openAccessibilityPrefs),
            keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc private func openAccessibilityPrefs() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Accessibility

    private func requestAccessibilityIfNeeded() {
        // "AXTrustedCheckOptionPrompt" is the stable string value of kAXTrustedCheckOptionPrompt
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        if AXIsProcessTrusted() {
            startInterceptor()
        } else {
            // Poll until granted, then start the interceptor
            DispatchQueue.global().async { [weak self] in
                while !AXIsProcessTrusted() {
                    Thread.sleep(forTimeInterval: 1.0)
                }
                DispatchQueue.main.async {
                    self?.startInterceptor()
                }
            }
        }
    }

    // MARK: - Interceptor

    private func startInterceptor() {
        guard AXIsProcessTrusted() else { return }
        guard interceptor == nil else { return }
        interceptor = BrightnessKeyInterceptor()
        interceptor?.start()
    }
}
