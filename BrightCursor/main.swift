// main.swift
// Application entry point. Using a manual NSApplication setup instead of @main
// on AppDelegate to avoid "top-level code" conflicts in Swift 6.

import AppKit

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.run()
