// PasteboardSupport.swift
// Provides Pasteboard Support for shared utilities.

import AppKit

func copyStringToPasteboard(_ text: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
}
