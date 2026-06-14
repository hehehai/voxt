import SwiftUI

struct MeetingDetailFollowUpSendButton: View {
    let action: () -> Void
    let isDisabled: Bool

    var body: some View {
        Button(action: action) {
            MeetingDetailFollowUpSendIcon()
                .frame(width: 18, height: 18)
        }
        .buttonStyle(MeetingAccentIconButtonStyle())
        .disabled(isDisabled)
    }
}

private struct MeetingAccentIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 34, height: 34)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(configuration.isPressed ? 0.82 : 0.96))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.28), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.94 : 1)
    }
}

private struct MeetingDetailFollowUpSendIcon: View {
    var body: some View {
        ZStack {
            MeetingDetailFollowUpSparkShape()
                .stroke(.white, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

            MeetingDetailFollowUpPlaneShape()
                .stroke(.white, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

            MeetingDetailFollowUpTrailShape()
                .stroke(Color.white.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}

private enum MeetingDetailIconGrid {
    static let size: CGFloat = 24

    static func point(in rect: CGRect, x: CGFloat, y: CGFloat) -> CGPoint {
        CGPoint(
            x: rect.minX + rect.width * x / size,
            y: rect.minY + rect.height * y / size
        )
    }
}

private struct MeetingDetailFollowUpSparkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: MeetingDetailIconGrid.point(in: rect, x: 19.83, y: 15.6))
        path.addLine(to: MeetingDetailIconGrid.point(in: rect, x: 18.69, y: 15.86))
        path.addCurve(
            to: MeetingDetailIconGrid.point(in: rect, x: 17.04, y: 17.51),
            control1: MeetingDetailIconGrid.point(in: rect, x: 17.87, y: 16.05),
            control2: MeetingDetailIconGrid.point(in: rect, x: 17.23, y: 16.69)
        )
        path.addLine(to: MeetingDetailIconGrid.point(in: rect, x: 16.77, y: 18.65))
        path.addCurve(
            to: MeetingDetailIconGrid.point(in: rect, x: 16.54, y: 18.65),
            control1: MeetingDetailIconGrid.point(in: rect, x: 16.74, y: 18.77),
            control2: MeetingDetailIconGrid.point(in: rect, x: 16.57, y: 18.77)
        )
        path.addLine(to: MeetingDetailIconGrid.point(in: rect, x: 16.28, y: 17.51))
        path.addCurve(
            to: MeetingDetailIconGrid.point(in: rect, x: 14.63, y: 15.86),
            control1: MeetingDetailIconGrid.point(in: rect, x: 16.09, y: 16.69),
            control2: MeetingDetailIconGrid.point(in: rect, x: 15.45, y: 16.05)
        )
        path.addLine(to: MeetingDetailIconGrid.point(in: rect, x: 13.49, y: 15.59))
        path.addCurve(
            to: MeetingDetailIconGrid.point(in: rect, x: 13.49, y: 15.36),
            control1: MeetingDetailIconGrid.point(in: rect, x: 13.37, y: 15.56),
            control2: MeetingDetailIconGrid.point(in: rect, x: 13.37, y: 15.39)
        )
        path.addLine(to: MeetingDetailIconGrid.point(in: rect, x: 14.63, y: 15.1))
        path.addCurve(
            to: MeetingDetailIconGrid.point(in: rect, x: 16.28, y: 13.45),
            control1: MeetingDetailIconGrid.point(in: rect, x: 15.45, y: 14.91),
            control2: MeetingDetailIconGrid.point(in: rect, x: 16.09, y: 14.27)
        )
        path.addLine(to: MeetingDetailIconGrid.point(in: rect, x: 16.55, y: 12.31))
        path.addCurve(
            to: MeetingDetailIconGrid.point(in: rect, x: 16.78, y: 12.31),
            control1: MeetingDetailIconGrid.point(in: rect, x: 16.58, y: 12.19),
            control2: MeetingDetailIconGrid.point(in: rect, x: 16.75, y: 12.19)
        )
        path.addLine(to: MeetingDetailIconGrid.point(in: rect, x: 17.04, y: 13.45))
        path.addCurve(
            to: MeetingDetailIconGrid.point(in: rect, x: 18.69, y: 15.1),
            control1: MeetingDetailIconGrid.point(in: rect, x: 17.23, y: 14.27),
            control2: MeetingDetailIconGrid.point(in: rect, x: 17.87, y: 14.91)
        )
        path.addLine(to: MeetingDetailIconGrid.point(in: rect, x: 19.83, y: 15.37))
        path.addCurve(
            to: MeetingDetailIconGrid.point(in: rect, x: 19.83, y: 15.6),
            control1: MeetingDetailIconGrid.point(in: rect, x: 19.95, y: 15.4),
            control2: MeetingDetailIconGrid.point(in: rect, x: 19.95, y: 15.57)
        )
        return path
    }
}

private struct MeetingDetailFollowUpPlaneShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: MeetingDetailIconGrid.point(in: rect, x: 12.31, y: 18.37))
        path.addLine(to: MeetingDetailIconGrid.point(in: rect, x: 9.51, y: 19.77))
        path.addCurve(
            to: MeetingDetailIconGrid.point(in: rect, x: 4.28, y: 14.54),
            control1: MeetingDetailIconGrid.point(in: rect, x: 3.75, y: 22.65),
            control2: MeetingDetailIconGrid.point(in: rect, x: 1.4, y: 20.29)
        )
        path.addLine(to: MeetingDetailIconGrid.point(in: rect, x: 5.15, y: 12.81))
        path.addCurve(
            to: MeetingDetailIconGrid.point(in: rect, x: 5.15, y: 11.2),
            control1: MeetingDetailIconGrid.point(in: rect, x: 5.37, y: 12.37),
            control2: MeetingDetailIconGrid.point(in: rect, x: 5.37, y: 11.64)
        )
        path.addLine(to: MeetingDetailIconGrid.point(in: rect, x: 4.28, y: 9.46))
        path.addCurve(
            to: MeetingDetailIconGrid.point(in: rect, x: 9.51, y: 4.23),
            control1: MeetingDetailIconGrid.point(in: rect, x: 1.4, y: 3.71),
            control2: MeetingDetailIconGrid.point(in: rect, x: 3.76, y: 1.35)
        )
        path.addLine(to: MeetingDetailIconGrid.point(in: rect, x: 18.07, y: 8.51))
        path.addCurve(
            to: MeetingDetailIconGrid.point(in: rect, x: 20.78, y: 12.92),
            control1: MeetingDetailIconGrid.point(in: rect, x: 20.46, y: 9.71),
            control2: MeetingDetailIconGrid.point(in: rect, x: 21.36, y: 11.37)
        )
        return path
    }
}

private struct MeetingDetailFollowUpTrailShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: MeetingDetailIconGrid.point(in: rect, x: 5.44, y: 12))
        path.addLine(to: MeetingDetailIconGrid.point(in: rect, x: 10.84, y: 12))
        return path
    }
}
