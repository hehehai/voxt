import SwiftUI
import Foundation

struct WaveformView: View {
    enum DisplayMode {
        case transcriptionText
        case statusOnly
    }

    var audioLevel: Float
    var isRecording: Bool
    var transcribedText: String
    var statusMessage: String = ""
    var actionItems: [String] = []
    var isEnhancing: Bool = false
    var isCompleting: Bool = false
    var displayMode: DisplayMode = .transcriptionText

    private let iconSlotSize = CGSize(width: 16, height: 28)
    private let barAreaHeight: CGFloat = 28

    // Number of bars in the waveform
    private let barCount = 16
    @State private var phases: [Double] = (0..<16).map { Double($0) * 0.4 }
    @State private var animTimer: Timer?
    @State private var appeared = false
    @State private var textScrollID = UUID()
    @State private var spinAngle: Double = 0
    @State private var actionPulse = false

    /// Whether we have text to show (drives expansion)
    private var displayText: String {
        let message = statusMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !message.isEmpty { return message }
        guard displayMode == .transcriptionText else { return "" }
        return sanitizedDisplayText(transcribedText)
    }

    private var hasText: Bool { !displayText.isEmpty }
    private var visibleActionItems: [String] { Array(actionItems.suffix(2)) }
    private var showsActionList: Bool { displayMode == .statusOnly && !visibleActionItems.isEmpty }

    private enum ActionBadgeStyle {
        case active
        case completed
        case warning
    }

    private func sanitizedDisplayText(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if !(trimmed.hasPrefix("{") || trimmed.hasPrefix("[")) {
            return trimmed
        }

        if let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data),
           let text = extractText(from: object),
           !text.isEmpty {
            return text
        }

        if let text = extractLooseText(from: trimmed), !text.isEmpty {
            return text
        }

        // Never hide transcription text completely when JSON-like parsing fails.
        // Falling back to raw text keeps the overlay informative.
        return trimmed
    }

    private func extractText(from object: Any) -> String? {
        if let value = object as? String {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let dict = object as? [String: Any] {
            for key in ["text", "transcript", "delta", "result_text", "content"] {
                if let value = dict[key], let extracted = extractText(from: value), !extracted.isEmpty {
                    return extracted
                }
            }
            for value in dict.values {
                if let extracted = extractText(from: value), !extracted.isEmpty {
                    return extracted
                }
            }
        }
        if let array = object as? [Any] {
            for value in array {
                if let extracted = extractText(from: value), !extracted.isEmpty {
                    return extracted
                }
            }
        }
        return nil
    }

    private func extractLooseText(from value: String) -> String? {
        let patterns = [
            #"(?:["']?text["']?\s*:\s*["'])([^"']+)(?:["'])"#,
            #"(?:["']?transcript["']?\s*:\s*["'])([^"']+)(?:["'])"#,
            #"(?:["']?delta["']?\s*:\s*["'])([^"']+)(?:["'])"#,
            #"(?:["']?text["']?\s*:\s*)([^,}\]]+)"#,
            #"(?:["']?transcript["']?\s*:\s*)([^,}\]]+)"#,
            #"(?:["']?delta["']?\s*:\s*)([^,}\]]+)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            guard let match = regex.firstMatch(in: value, options: [], range: range),
                  match.numberOfRanges > 1,
                  let textRange = Range(match.range(at: 1), in: value) else {
                continue
            }
            var result = String(value[textRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if (result.hasPrefix("\"") && result.hasSuffix("\"")) ||
                (result.hasPrefix("'") && result.hasSuffix("'")) {
                result.removeFirst()
                result.removeLast()
                result = result.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !result.isEmpty { return result }
        }
        return nil
    }

    /// Keep expanded layout while text exists to avoid UI jumps during LLM processing.
    private var isCompact: Bool { !hasText }

    private var cornerRadius: CGFloat { isCompact ? 24 : 20 }
    private var textOverflows: Bool { displayText.count > 38 }

    var body: some View {
        VStack(spacing: isCompact ? 0 : 8) {
            HStack(spacing: 10) {
                // Icon: spinner when enhancing, voxt icon otherwise
                if isCompleting {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                        .frame(width: iconSlotSize.width, height: iconSlotSize.height)
                        .transition(.opacity)
                } else if isEnhancing {
                    processingSpinner
                } else {
                    Image("voxt")
                        .resizable()
                        .renderingMode(.template)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                        .frame(width: iconSlotSize.width, height: iconSlotSize.height)
                        .foregroundStyle(.white)
                        .opacity(0.9)
                        .transition(.opacity)
                }
                
                // Bars: processing shimmer when enhancing, waveform otherwise
                if isEnhancing {
                    processingBars
                        .transition(.opacity)
                } else {
                    waveformBars
                        .transition(.opacity)
                }
            }
            .frame(height: barAreaHeight)
            .animation(.easeInOut(duration: 0.25), value: isEnhancing)

            if showsActionList {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(visibleActionItems.enumerated()), id: \.offset) { index, item in
                        let isLatest = index == visibleActionItems.count - 1
                        let badgeStyle = actionBadgeStyle(for: item, isLatest: isLatest)
                        HStack(alignment: .center, spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(badgeBackground(for: badgeStyle))
                                    .scaleEffect(badgeStyle == .active && actionPulse ? 1.08 : 1.0)
                                Image(systemName: badgeIcon(for: badgeStyle))
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(badgeForeground(for: badgeStyle))
                            }
                            .frame(width: 16, height: 16)
                            Text(item)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(textForeground(for: badgeStyle, isLatest: isLatest))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(rowBackground(for: badgeStyle, isLatest: isLatest))
                        )
                    }
                }
                .frame(maxWidth: 260, alignment: .leading)
                .transition(.opacity)
            } else if hasText {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            Text(displayText)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .id(textScrollID)

                            Spacer().frame(width: 4)
                        }
                    }
                    .frame(maxWidth: 260)
                    .mask(
                        HStack(spacing: 0) {
                            if textOverflows {
                                LinearGradient(
                                    colors: [.clear, .white],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(width: 16)
                                .transition(.opacity)
                            }
                            Color.white
                        }
                    )
                    .onChange(of: displayText) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(textScrollID, anchor: .trailing)
                            }
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, isCompact ? 14 : 20)
        .padding(.vertical, isCompact ? 10 : 12)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.black.opacity(0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                )
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.55, blendDuration: 0.1), value: isCompact)
        .animation(.spring(response: 0.4, dampingFraction: 0.55, blendDuration: 0.1), value: hasText)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .scaleEffect(appeared ? 1.0 : 0.5, anchor: .top)
        .opacity(appeared ? 1.0 : 0.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.5, blendDuration: 0.1), value: appeared)
        .onAppear {
            startAnimating()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                appeared = true
            }
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                actionPulse = true
            }
        }
        .onDisappear {
            stopAnimating()
            appeared = false
            actionPulse = false
        }
    }

    private func actionBadgeStyle(for item: String, isLatest: Bool) -> ActionBadgeStyle {
        let lowercased = item.lowercased()
        if lowercased.contains("fail")
            || lowercased.contains("cancel")
            || lowercased.contains("error")
            || lowercased.contains("unsupported")
            || item.contains("失败")
            || item.contains("取消")
            || item.contains("错误") {
            return .warning
        }
        return isLatest ? .active : .completed
    }

    private func badgeIcon(for style: ActionBadgeStyle) -> String {
        switch style {
        case .active:
            return "arrow.triangle.2.circlepath"
        case .completed:
            return "checkmark"
        case .warning:
            return "exclamationmark"
        }
    }

    private func badgeBackground(for style: ActionBadgeStyle) -> Color {
        switch style {
        case .active:
            return .white.opacity(0.16)
        case .completed:
            return .white.opacity(0.09)
        case .warning:
            return Color(red: 0.85, green: 0.38, blue: 0.28).opacity(0.22)
        }
    }

    private func badgeForeground(for style: ActionBadgeStyle) -> Color {
        switch style {
        case .active:
            return .white.opacity(0.92)
        case .completed:
            return .white.opacity(0.72)
        case .warning:
            return Color(red: 1.0, green: 0.82, blue: 0.76)
        }
    }

    private func rowBackground(for style: ActionBadgeStyle, isLatest: Bool) -> Color {
        switch style {
        case .active:
            return .white.opacity(isLatest ? 0.07 : 0.05)
        case .completed:
            return .white.opacity(0.035)
        case .warning:
            return Color(red: 0.85, green: 0.38, blue: 0.28).opacity(0.10)
        }
    }

    private func textForeground(for style: ActionBadgeStyle, isLatest: Bool) -> Color {
        switch style {
        case .active:
            return .white.opacity(isLatest ? 0.92 : 0.74)
        case .completed:
            return .white.opacity(isLatest ? 0.84 : 0.68)
        case .warning:
            return Color(red: 1.0, green: 0.85, blue: 0.80)
        }
    }

    // MARK: - Waveform bars (recording state)

    private var waveformBars: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.98), Color.white.opacity(0.80)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3.2, height: barHeight(for: index))
                    .shadow(color: .white.opacity(glowOpacity(for: index)), radius: 3, x: 0, y: 0)
                    .animation(.easeInOut(duration: 0.1), value: audioLevel)
            }
        }
        .frame(height: barAreaHeight)
    }

    // MARK: - Processing bars (enhancing state)

    private var processingBars: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.white.opacity(processingBarOpacity(for: index)))
                    .frame(width: 2.5, height: processingBarHeight(for: index))
            }
        }
        .frame(height: barAreaHeight)
    }

    // MARK: - Processing spinner

    private var processingSpinner: some View {
        Circle()
            .trim(from: 0.14, to: 0.82)
            .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 1.35, lineCap: .round))
            .frame(width: 12, height: 12)
            .frame(width: iconSlotSize.width, height: iconSlotSize.height)
            .rotationEffect(.degrees(spinAngle))
            .onAppear {
                spinAngle = 0
                withAnimation(.linear(duration: 0.68).repeatForever(autoreverses: false)) {
                    spinAngle = 360
                }
            }
            .onDisappear {
                spinAngle = 0
            }
    }

    // MARK: - Bar helpers

    private func barHeight(for index: Int) -> CGFloat {
        let level = normalizedAudioLevel(audioLevel)
        let phase = phases[index]
        let sine = (sin(phase) + 1) / 2
        let minH: CGFloat = 4
        let maxH: CGFloat = 26

        if isRecording {
            let driven = minH + (maxH - minH) * level * CGFloat(sine * 0.72 + 0.28)
            return max(minH, driven)
        } else {
            return minH + (maxH * 0.18) * CGFloat(sine)
        }
    }

    private func glowOpacity(for index: Int) -> Double {
        guard isRecording else { return 0.08 }
        let level = Double(normalizedAudioLevel(audioLevel))
        let phase = phases[index]
        let sine = (sin(phase * 1.15) + 1) / 2
        return min(0.35, 0.08 + level * 0.27 * sine)
    }

    private func normalizedAudioLevel(_ raw: Float) -> CGFloat {
        let clamped = max(0, min(raw, 1))
        // Visual gain curve: make low/mid volumes much more visible.
        let gained = min(1.0, pow(Double(clamped), 0.62) * 1.55)
        return CGFloat(gained)
    }

    /// Gentle wave pattern for processing bars — subtle, low variance
    private func processingBarHeight(for index: Int) -> CGFloat {
        let phase = phases[index]
        let sine = (sin(phase) + 1) / 2
        let minH: CGFloat = 6
        let maxH: CGFloat = 10
        return minH + (maxH - minH) * CGFloat(sine)
    }

    /// Shimmer opacity for processing bars
    private func processingBarOpacity(for index: Int) -> Double {
        let phase = phases[index]
        let sine = (sin(phase * 1.2) + 1) / 2
        return 0.35 + 0.4 * sine
    }

    // MARK: - Animation timer

    private func startAnimating() {
        animTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            Task { @MainActor in
                let speed: Double = isRecording ? 0.18 : (isEnhancing ? 0.08 : 0.05)
                for i in 0..<barCount {
                    phases[i] += speed + Double(i) * 0.008
                }
            }
        }
    }

    private func stopAnimating() {
        animTimer?.invalidate()
        animTimer = nil
    }
}
