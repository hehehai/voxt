// SelectedTextSystemSelectionSupport.swift
// Capability-based policy for system selection probing (no AppKit UI).

import Foundation
import ApplicationServices

enum SelectedTextSystemSelectionSupport {
    /// Hard gate: a caret-only range (`length == 0`) must not count as a selection.
    static func hasNonEmptySelectedTextRange(length: CFIndex) -> Bool {
        length > 0
    }

    /// Editors that implement "Cmd+C with no selection copies the current line"
    /// (VS Code `editor.emptySelectionClipboard`, Sublime, Zed, JetBrains, etc.).
    ///
    /// This is a clipboard-semantics capability class. Many of these apps also
    /// fail AX focus lookup with `kAXErrorCannotComplete` (-25204), so
    /// "focused == nil" alone cannot mean "safe to Cmd+C" — that path remains
    /// necessary for AX-dead apps such as WeChat, but must stay denied here.
    static func copiesCurrentLineWhenSelectionEmpty(bundleID: String?) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return false }

        let exactIDs: Set<String> = [
            "com.microsoft.VSCode",
            "com.microsoft.VSCodeInsiders",
            "com.microsoft.VSCodeExploration",
            "com.visualstudio.code.oss",
            "com.visualstudio.code",
            "com.vscodium",
            "com.google.antigravity",
            "com.sublimetext.3",
            "com.sublimetext.4",
            "dev.zed.Zed",
            "dev.zed.Zed-Preview",
            "com.trae.app",
            "com.trae.solo.app",
            "cn.trae.app",
            "com.qoder.app"
        ]
        if exactIDs.contains(bundleID) {
            return true
        }

        let prefixes = [
            "com.todesktop.",
            "com.jetbrains.",
            "com.exafunction.",
            "com.trae.",
            "cn.trae.",
            "com.qoder."
        ]
        if prefixes.contains(where: bundleID.hasPrefix) {
            return true
        }

        let lowered = bundleID.lowercased()
        return lowered.contains("vscode") || lowered.contains("vscodium")
    }

    /// Whether Cmd+C may run after all non-destructive reads missed.
    ///
    /// Capability rule (not per-app special cases):
    /// - caret-only range (`length == 0`) → deny
    /// - non-empty range → allow (recover text when attributes are empty)
    /// - no focused element:
    ///   - deny when the frontmost app's clipboard class invents a line on empty selection
    ///   - allow otherwise (AX-dead apps that do not invent clipboard content)
    /// - focused element but no range attribute:
    ///   - browser → allow
    ///   - otherwise → deny
    ///
    /// Clipboard-shape heuristics are intentionally not used: they both miss real
    /// whole-line selections and fail to catch empty-selection line copies without EOL.
    static func shouldAttemptSimulatedCopy(
        focusedElementAvailable: Bool,
        selectedTextRange: CFRange?,
        isBrowser: Bool,
        copiesLineOnEmptySelection: Bool
    ) -> Bool {
        if focusedElementAvailable, let selectedTextRange {
            return selectedTextRange.length > 0
        }
        if !focusedElementAvailable {
            return !copiesLineOnEmptySelection
        }
        return isBrowser
    }

    /// Range attribute present with `length == 0` means caret-only; further probes cannot help.
    static func isConfirmedCaretOnly(selectedTextRange: CFRange?) -> Bool {
        guard let selectedTextRange else { return false }
        return selectedTextRange.length == 0
    }

    /// AppleScript ran without an execution error and returned empty/whitespace selection text.
    /// Dialect retries are only useful when the script form itself fails.
    static func isDefinitiveEmptyBrowserSelection(output: String?, hadExecutionError: Bool) -> Bool {
        guard !hadExecutionError, let output else { return false }
        return output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Stable deny reason for logs / diagnostics after copy policy rejects.
    static func denialDetail(
        allowCopy: Bool,
        focusedElementAvailable: Bool,
        selectedTextRange: CFRange?,
        isBrowser: Bool,
        copiesLineOnEmptySelection: Bool
    ) -> String {
        if allowCopy {
            return "copy-missed"
        }
        if !focusedElementAvailable, copiesLineOnEmptySelection {
            return "ax-focus-unavailable-line-copy-editor"
        }
        if focusedElementAvailable, selectedTextRange?.length == 0 {
            return "confirmed-caret-only"
        }
        if focusedElementAvailable, selectedTextRange == nil, !isBrowser {
            return "focused-without-range-non-browser"
        }
        return "copy-denied"
    }
}
