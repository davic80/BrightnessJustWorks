// AppDelegate.swift
// Sets up the menu bar icon, requests Accessibility permission on first launch,
// and wires together BrightnessKeyInterceptor with DisplayRouter.
// NOTE: No @main attribute — entry point is main.swift.

import AppKit
import ApplicationServices

@MainActor
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
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let title = NSMenuItem(title: "BrightnessJustWorks \(version)", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Grant Accessibility Access…",
            action: #selector(openAccessibilityPrefs),
            keyEquivalent: ""))
        menu.addItem(NSMenuItem(
            title: "Uninstall…",
            action: #selector(uninstall),
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

    // MARK: - Uninstall

    @objc private func uninstall() {
        let alert = NSAlert()
        alert.messageText = "Uninstall BrightnessJustWorks?"
        alert.informativeText = """
            This will:
            • Remove BrightnessJustWorks from /Applications
            • Revoke its Accessibility permission
            • Quit the app

            This action cannot be undone.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        // 1. Revoke Accessibility TCC entry
        let resetTask = Process()
        resetTask.launchPath = "/usr/bin/tccutil"
        resetTask.arguments = ["reset", "Accessibility", "com.brightnessjustworks.app"]
        try? resetTask.run()
        resetTask.waitUntilExit()

        // 2. Remove the app bundle from /Applications
        let appPath = "/Applications/BrightnessJustWorks.app"
        if FileManager.default.fileExists(atPath: appPath) {
            try? FileManager.default.removeItem(atPath: appPath)
        }

        // 3. Quit
        NSApp.terminate(nil)
    }

    // MARK: - Accessibility

    private func requestAccessibilityIfNeeded() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        if AXIsProcessTrusted() {
            startInterceptor()
        } else {
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
