// DictionaryHeaderActions.swift
// Provides Dictionary Header Actions for dictionary settings.

import SwiftUI
import AppKit

struct DictionaryHeaderMenuAction {
    let title: String
    let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.title = title
        self.handler = handler
    }
}

struct DictionaryHeaderActionMenuButton: View {
    let actions: [DictionaryHeaderMenuAction]
    var accessibilityLabel = AppLocalization.localizedString("More")

    var body: some View {
        Menu {
            ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                Button(action.title, action: action.handler)
            }
        } label: {
            DictionaryHeaderMenuButtonLabel()
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct DictionaryHeaderMenuButtonLabel: View {
    @State private var isHovered = false

    var body: some View {
        SettingsMoreMenuIconView(size: 15)
            .frame(width: 15, height: 15)
            .frame(width: 30, height: 30)
            .foregroundStyle(Color.secondary)
            .background(fillColor)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(SettingsUIStyle.subtleBorderColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onHover { isHovered = $0 }
    }

    private var fillColor: Color {
        if isHovered {
            return SettingsUIStyle.subtleFillColor.opacity(0.72)
        }
        return SettingsUIStyle.subtleFillColor
    }
}
