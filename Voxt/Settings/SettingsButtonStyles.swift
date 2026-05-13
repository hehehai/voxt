import SwiftUI

struct SettingsSidebarItemButtonStyle: ButtonStyle {
    var isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(isActive ? Color.white : Color.primary)
            .padding(.horizontal, SettingsUIStyle.sidebarItemHorizontalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: SettingsUIStyle.sidebarItemHeight)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isActive
                            ? Color.accentColor.opacity(configuration.isPressed ? 0.84 : 1)
                            : Color.clear
                    )
            )
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}

struct SettingsPillButtonStyle: ButtonStyle {
    enum Tone {
        case neutral
        case destructive
    }

    var tone: Tone = .neutral
    var horizontalPadding: CGFloat = 12
    var height: CGFloat = 32

    func makeBody(configuration: Configuration) -> some View {
        let foreground: Color = tone == .destructive ? .red : .primary
        let fill: Color = tone == .destructive
            ? .red.opacity(configuration.isPressed ? 0.16 : 0.10)
            : SettingsUIStyle.subtleFillColor.opacity(configuration.isPressed ? 0.88 : 1)
        let stroke: Color = tone == .destructive ? .red.opacity(0.22) : SettingsUIStyle.subtleBorderColor

        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(foreground.opacity(configuration.isPressed ? 0.72 : 0.92))
            .padding(.horizontal, horizontalPadding)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1)
            )
    }
}

struct SettingsPrimaryButtonStyle: ButtonStyle {
    var horizontalPadding: CGFloat = 14
    var height: CGFloat = 34

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.82 : 0.96))
            .padding(.horizontal, horizontalPadding)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(configuration.isPressed ? 0.82 : 0.96))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.28), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.92 : 1)
    }
}

struct SettingsCompactActionButtonStyle: ButtonStyle {
    enum Tone {
        case neutral
        case destructive
    }

    var tone: Tone = .neutral
    var height: CGFloat = 28
    var horizontalPadding: CGFloat = 9

    func makeBody(configuration: Configuration) -> some View {
        let foreground: Color = tone == .destructive ? .red : .primary
        let fill: Color = tone == .destructive
            ? .red.opacity(configuration.isPressed ? 0.16 : 0.10)
            : SettingsUIStyle.subtleFillColor.opacity(configuration.isPressed ? 0.88 : 1)
        let stroke: Color = tone == .destructive ? .red.opacity(0.22) : SettingsUIStyle.subtleBorderColor

        return configuration.label
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(foreground.opacity(configuration.isPressed ? 0.8 : 0.92))
            .padding(.horizontal, horizontalPadding)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.94 : 1)
    }
}

struct SettingsCompactIconButtonStyle: ButtonStyle {
    var tone: SettingsCompactActionButtonStyle.Tone = .neutral
    var size: CGFloat = 28

    func makeBody(configuration: Configuration) -> some View {
        let foreground: Color = tone == .destructive ? .red : .secondary
        let fill: Color = tone == .destructive
            ? .red.opacity(configuration.isPressed ? 0.16 : 0.10)
            : SettingsUIStyle.subtleFillColor.opacity(configuration.isPressed ? 0.88 : 1)
        let stroke: Color = tone == .destructive ? .red.opacity(0.22) : SettingsUIStyle.subtleBorderColor

        return configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.92 : 1)
    }
}

struct SettingsInlineSelectorButtonStyle: ButtonStyle {
    var isEmphasized = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isEmphasized ? Color.primary : Color.primary.opacity(0.92))
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: SettingsUIStyle.controlCornerRadius, style: .continuous)
                    .fill(SettingsUIStyle.subtleFillColor.opacity(configuration.isPressed ? 0.88 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: SettingsUIStyle.controlCornerRadius, style: .continuous)
                    .strokeBorder(SettingsUIStyle.subtleBorderColor.opacity(isEmphasized ? 1 : 0.92), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.92 : 1)
    }
}

struct SettingsStatusButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.16 : 0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(tint.opacity(0.28), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}

struct SettingsSegmentedButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.4) : .clear, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}
