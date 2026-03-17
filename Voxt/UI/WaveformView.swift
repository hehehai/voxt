import SwiftUI
import Foundation
import AppKit

struct WaveformView: View {
    var displayMode: OverlayDisplayMode
    var sessionIconMode: OverlaySessionIconMode
    var audioLevel: Float
    var isRecording: Bool
    var transcribedText: String
    var statusMessage: String = ""
    var isEnhancing: Bool = false
    var isCompleting: Bool = false
    var answerTitle: String = ""
    var answerContent: String = ""
    var onClose: () -> Void = {}

    private let iconSlotSize = CGSize(width: 16, height: 28)
    private let barAreaHeight: CGFloat = 28
    private let barCount = 16

    @State private var phases: [Double] = (0..<16).map { Double($0) * 0.4 }
    @State private var animTimer: Timer?
    @State private var appeared = false
    @State private var textScrollID = UUID()
    @State private var didCopyAnswer = false
    @State private var copyFeedbackToken = UUID()

    private var displayText: String {
        let message = statusMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !message.isEmpty { return message }
        return sanitizedDisplayText(transcribedText)
    }

    private var hasText: Bool { !displayText.isEmpty }
    private var isAnswerMode: Bool { displayMode == .answer }
    private var isCompact: Bool { !hasText && !isAnswerMode }
    private var cornerRadius: CGFloat { isAnswerMode ? 28 : (isCompact ? 24 : 20) }
    private var textOverflows: Bool { displayText.count > 38 }

    var body: some View {
        Group {
            if isAnswerMode {
                answerCard
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            } else {
                compactCard
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .padding(.horizontal, isAnswerMode ? 18 : (isCompact ? 14 : 20))
        .padding(.vertical, isAnswerMode ? 16 : (isCompact ? 10 : 12))
        .background(cardBackground)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: displayMode)
        .animation(.spring(response: 0.4, dampingFraction: 0.55, blendDuration: 0.1), value: isCompact)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .scaleEffect(appeared ? 1.0 : 0.5, anchor: .top)
        .opacity(appeared ? 1.0 : 0.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.5, blendDuration: 0.1), value: appeared)
        .onAppear {
            startAnimating()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                appeared = true
            }
        }
        .onDisappear {
            stopAnimating()
            appeared = false
        }
    }

    private var compactCard: some View {
        VStack(spacing: isCompact ? 0 : 8) {
            HStack(spacing: 10) {
                if isCompleting {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                        .frame(width: iconSlotSize.width, height: iconSlotSize.height)
                        .transition(.opacity)
                } else {
                    compactModeIcon
                        .frame(width: iconSlotSize.width, height: iconSlotSize.height)
                        .transition(.opacity)
                }

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

            if hasText {
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
    }

    private var answerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                AnswerIconView()
                    .frame(width: 20, height: 20)

                Text(answerTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "AI Answer") : answerTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 12)

                AnswerHeaderActionButton(
                    accessibilityLabel: String(localized: "Copy")
                ) {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(answerContent, forType: .string)
                    let token = UUID()
                    copyFeedbackToken = token
                    didCopyAnswer = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        guard copyFeedbackToken == token else { return }
                        didCopyAnswer = false
                    }
                } label: {
                    if didCopyAnswer {
                        CopySuccessIconView()
                            .frame(width: 15, height: 15)
                    } else {
                        CopyIconView()
                            .frame(width: 15, height: 15)
                    }
                }

                AnswerHeaderActionButton(
                    accessibilityLabel: String(localized: "Close")
                ) {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }

            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)

            ScrollView(.vertical, showsIndicators: true) {
                Text(answerContent)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.trailing, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: 220, alignment: .topLeading)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.black.opacity(0.82))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            )
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

    @ViewBuilder
    private var compactModeIcon: some View {
        switch sessionIconMode {
        case .transcription:
            TranscriptionModeIconView()
                .frame(width: 16, height: 16)
                .opacity(0.92)
        case .translation:
            TranslationModeIconView()
                .frame(width: 16, height: 16)
                .opacity(0.92)
        case .rewrite:
            RewriteModeIconView()
                .frame(width: 16, height: 16)
                .opacity(0.92)
        }
    }

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
        let gained = min(1.0, pow(Double(clamped), 0.62) * 1.55)
        return CGFloat(gained)
    }

    private func processingBarHeight(for index: Int) -> CGFloat {
        let phase = phases[index]
        let sine = (sin(phase) + 1) / 2
        let minH: CGFloat = 6
        let maxH: CGFloat = 10
        return minH + (maxH - minH) * CGFloat(sine)
    }

    private func processingBarOpacity(for index: Int) -> Double {
        let phase = phases[index]
        let sine = (sin(phase * 1.2) + 1) / 2
        return 0.35 + 0.4 * sine
    }

    private func startAnimating() {
        animTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            Task { @MainActor in
                let speed: Double
                switch displayMode {
                case .recording:
                    speed = isRecording ? 0.18 : 0.05
                case .processing:
                    speed = 0.08
                case .answer:
                    speed = 0.05
                }
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

private struct AnswerIconView: View {
    var body: some View {
        ZStack {
            SVGPathShape(pathData: "M21.25 13.0101C21.11 13.8701 20.84 14.6801 20.51 15.4501C20.37 15.2701 20.25 15.0601 20.18 14.8301L19.77 13.3701C19.51 12.6801 18.85 12.2401 18.08 12.2401C17.33 12.2401 16.69 12.7201 16.42 13.4101L16.35 13.6401L16.02 14.8601C15.85 15.4601 15.4 15.9201 14.78 16.0901L13.55 16.4101C12.73 16.6401 12.2 17.3501 12.2 18.1701C12.2 18.9901 12.73 19.6901 13.51 19.9101L14.78 20.2501C14.98 20.3101 15.16 20.4001 15.32 20.5201C14.69 20.7801 14.05 21.0001 13.35 21.1301C11.1 21.5601 8.93998 21.2301 7.08998 20.3501C6.78998 20.2101 6.28998 20.1401 5.95998 20.2201C5.26998 20.3801 4.09998 20.6701 3.10998 20.9001C2.15998 21.1301 1.57998 20.5501 1.80998 19.6001L2.48998 16.7601C2.56998 16.4301 2.49998 15.9201 2.35998 15.6201C1.51998 13.8501 1.17998 11.8001 1.52998 9.64006C2.19998 5.49006 5.54998 2.14006 9.69998 1.46006C16.54 0.340058 22.37 6.17006 21.25 13.0101Z")
                .fill(.white.opacity(0.4))

            SVGPathShape(pathData: "M17.09 9.98003C17.01 10.02 16.92 10.03 16.83 10.03C16.52 10.03 16.24 9.85003 16.13 9.55003C15.62 8.20003 14.56 7.12003 13.21 6.60003C12.83 6.45003 12.64 6.02003 12.78 5.63003C12.93 5.25003 13.37 5.06003 13.75 5.20003C15.5 5.88003 16.87 7.27003 17.53 9.02003C17.68 9.41003 17.48 9.84003 17.09 9.98003Z")
                .fill(.white)

            SVGPathShape(pathData: "M22.6 18.2C22.6 18.29 22.55 18.49 22.31 18.57L21.04 18.92C19.95 19.22 19.13 20.04 18.83 21.13L18.49 22.37C18.41 22.65 18.19 22.68 18.09 22.68C17.99 22.68 17.77 22.65 17.69 22.37L17.35 21.12C17.05 20.04 16.22 19.22 15.14 18.92L13.89 18.58C13.62 18.5 13.59 18.27 13.59 18.18C13.59 18.08 13.62 17.85 13.89 17.77L15.15 17.44C16.23 17.13 17.05 16.31 17.35 15.23L17.71 13.92C17.8 13.7 18 13.67 18.09 13.67C18.18 13.67 18.39 13.7 18.47 13.9L18.83 15.22C19.13 16.3 19.96 17.12 21.04 17.43L22.33 17.78C22.59 17.88 22.6 18.11 22.6 18.19V18.2Z")
                .fill(.white)
        }
    }
}

private struct TranscriptionModeIconView: View {
    private let viewport = CGSize(width: 392, height: 392)

    var body: some View {
        ZStack {
            SVGPathShape(
                pathData: "M196.002 358.194C113.682 358.194 46.5516 291.227 46.5516 208.744V178.037C46.5516 171.667 51.7782 166.604 57.9849 166.604C64.1916 166.604 69.4182 171.83 69.4182 178.037V208.744C69.4182 278.487 126.095 335.164 195.838 335.164C265.582 335.164 322.258 278.487 322.258 208.744V178.037C322.258 171.667 327.485 166.604 333.692 166.604C339.898 166.604 345.125 171.83 345.125 178.037V208.744C345.452 291.227 278.322 358.194 196.002 358.194Z",
                viewport: viewport
            )
            .fill(.white)

            SVGPathShape(
                pathData: "M195.998 32.666C141.118 32.666 96.3651 77.4194 96.3651 132.299V208.903C96.3651 263.783 141.118 308.536 195.998 308.536C250.878 308.536 295.632 263.783 295.632 208.903V132.299C295.632 77.4194 250.878 32.666 195.998 32.666ZM231.605 172.969C230.462 177.379 226.378 180.319 221.968 180.319C221.152 180.319 220.172 180.156 219.355 179.993C202.695 175.419 185.055 175.419 168.395 179.993C163.005 181.463 157.615 178.359 156.145 172.969C154.675 167.743 157.778 162.189 163.168 160.719C183.258 155.166 204.492 155.166 224.582 160.719C229.972 162.189 233.075 167.579 231.605 172.969ZM245.488 127.726C244.018 131.809 240.262 134.259 236.178 134.259C235.035 134.259 233.892 134.096 232.748 133.606C207.758 124.459 180.318 124.459 155.328 133.606C150.102 135.566 144.385 132.953 142.425 127.726C140.628 122.663 143.242 116.946 148.468 114.986C177.868 104.369 210.208 104.369 239.445 114.986C244.672 116.946 247.285 122.663 245.488 127.726Z",
                viewport: viewport
            )
            .fill(.white)
        }
    }
}

private struct TranslationModeIconView: View {
    private let viewport = CGSize(width: 392, height: 392)

    var body: some View {
        ZStack {
            SVGPathShape(
                pathData: "M196.45 358.194C114.13 358.194 47 291.227 47 208.744V178.037C47 171.667 52.2267 166.604 58.4333 166.604C64.64 166.604 69.8667 171.83 69.8667 178.037V208.744C69.8667 278.487 126.543 335.164 196.287 335.164C266.03 335.164 322.707 278.487 322.707 208.744V178.037C322.707 171.667 327.933 166.604 334.14 166.604C340.347 166.604 345.573 171.83 345.573 178.037V208.744C345.9 291.227 278.77 358.194 196.45 358.194Z",
                viewport: viewport
            )
            .fill(.white)

            SVGPathShape(
                pathData: "M196.634 32.666C251.514 32.6663 296.267 77.42 296.267 132.3V208.902C296.267 263.782 251.514 308.536 196.634 308.536C141.754 308.536 97 263.782 97 208.902V132.3C97 77.4198 141.754 32.666 196.634 32.666ZM196.917 107.25C190.98 107.25 186.167 112.063 186.167 118V121.954H153.217C147.28 121.954 142.467 126.767 142.467 132.704C142.467 138.641 147.28 143.454 153.217 143.454H196.641C196.733 143.456 196.825 143.461 196.917 143.461C197.01 143.461 197.102 143.456 197.194 143.454H207.243C205.333 153.88 200.751 163.255 194.313 170.833C193.377 171.58 192.598 172.454 191.982 173.413C181.919 183.897 168.067 190.322 153 190.322C147.063 190.322 142.25 195.135 142.25 201.072C142.25 207.009 147.063 211.822 153 211.822C170.986 211.822 187.444 205.437 200.467 194.799C211.368 205.224 225.4 211.826 241.049 211.826C246.986 211.826 251.799 207.013 251.799 201.076C251.799 195.139 246.986 190.326 241.049 190.326C231.698 190.326 222.62 186.355 215.094 179.049C222.336 168.74 227.233 156.584 229.001 143.454H241.051C246.988 143.454 251.801 138.641 251.801 132.704C251.801 126.767 246.988 121.954 241.051 121.954H221.105C220.419 121.817 219.71 121.743 218.983 121.743C218.257 121.743 217.547 121.817 216.861 121.954H207.667V118C207.667 112.063 202.854 107.25 196.917 107.25Z",
                viewport: viewport
            )
            .fill(.white)
        }
    }
}

private struct RewriteModeIconView: View {
    private let viewport = CGSize(width: 392, height: 392)

    var body: some View {
        ZStack {
            SVGPathShape(
                pathData: "M196.002 358.194C113.682 358.194 46.5516 291.227 46.5516 208.744V178.037C46.5516 171.667 51.7782 166.604 57.9849 166.604C64.1916 166.604 69.4182 171.83 69.4182 178.037V208.744C69.4182 278.487 126.095 335.164 195.838 335.164C265.582 335.164 322.258 278.487 322.258 208.744V178.037C322.258 171.667 327.485 166.604 333.692 166.604C339.898 166.604 345.125 171.83 345.125 178.037V208.744C345.452 291.227 278.322 358.194 196.002 358.194Z",
                viewport: viewport
            )
            .fill(.white)

            SVGPathShape(
                pathData: "M195.634 32.666C250.513 32.6662 295.266 77.4199 295.266 132.3V208.902C295.266 263.782 250.513 308.536 195.634 308.536C140.754 308.536 95.9998 263.782 95.9998 208.902V132.3C95.9998 77.4198 140.754 32.666 195.634 32.666ZM203.368 106.027C199.859 96.766 188.203 101.397 186.241 111.035C176.508 134.039 164.435 149.287 146.478 158.135C138.745 161.636 137.575 173.948 144.931 175.491C167.189 181.327 179.676 194.015 187.787 208.661C192.427 217.132 201.784 212.125 204.123 202.863C213.856 179.822 227.89 166.757 245.432 157.909C253.166 154.408 252.788 144.054 244.639 141.381C222.419 135.959 209.555 122.104 203.368 106.027Z",
                viewport: viewport
            )
            .fill(.white)
        }
    }
}

private struct CopyIconView: View {
    var body: some View {
        ZStack {
            SVGPathShape(pathData: "M15.5 13.15H13.33C11.55 13.15 10.1 11.71 10.1 9.92V7.75C10.1 7.34 9.77 7 9.35 7H6.18C3.87 7 2 8.5 2 11.18V17.82C2 20.5 3.87 22 6.18 22H12.07C14.38 22 16.25 20.5 16.25 17.82V13.9C16.25 13.48 15.91 13.15 15.5 13.15Z")
                .fill(.white.opacity(0.4))

            SVGPathShape(pathData: "M17.8198 2H15.8498H14.7598H11.9298C9.66977 2 7.83977 3.44 7.75977 6.01C7.81977 6.01 7.86977 6 7.92977 6H10.7598H11.8498H13.8198C16.1298 6 17.9998 7.5 17.9998 10.18V12.15V14.86V16.83C17.9998 16.89 17.9898 16.94 17.9898 16.99C20.2198 16.92 21.9998 15.44 21.9998 12.83V10.86V8.15V6.18C21.9998 3.5 20.1298 2 17.8198 2Z")
                .fill(.white)

            SVGPathShape(pathData: "M11.9801 7.14975C11.6701 6.83975 11.1401 7.04975 11.1401 7.47975V10.0998C11.1401 11.1998 12.0701 12.0998 13.2101 12.0998C13.9201 12.1098 14.9101 12.1098 15.7601 12.1098C16.1901 12.1098 16.4101 11.6098 16.1101 11.3098C15.0201 10.2198 13.0801 8.26975 11.9801 7.14975Z")
                .fill(.white)
        }
    }
}

private struct CopySuccessIconView: View {
    var body: some View {
        ZStack {
            SVGPathShape(pathData: "M15.5 13.15H13.33C11.55 13.15 10.1 11.71 10.1 9.92V7.75C10.1 7.34 9.77 7 9.35 7H6.18C3.87 7 2 8.5 2 11.18V17.82C2 20.5 3.87 22 6.18 22H12.07C14.38 22 16.25 20.5 16.25 17.82V13.9C16.25 13.48 15.91 13.15 15.5 13.15Z")
                .fill(.white)

            SVGPathShape(pathData: "M17.82 2H15.85H14.76H11.93C9.67001 2 7.84001 3.44 7.76001 6.01C7.82001 6.01 7.87001 6 7.93001 6H10.76H11.85H13.82C16.13 6 18 7.5 18 10.18V12.15V14.86V16.83C18 16.89 17.99 16.94 17.99 16.99C20.22 16.92 22 15.44 22 12.83V10.86V8.15V6.18C22 3.5 20.13 2 17.82 2Z")
                .fill(.white)

            SVGPathShape(pathData: "M11.9799 7.14975C11.6699 6.83975 11.1399 7.04975 11.1399 7.47975V10.0998C11.1399 11.1998 12.0699 12.0998 13.2099 12.0998C13.9199 12.1098 14.9099 12.1098 15.7599 12.1098C16.1899 12.1098 16.4099 11.6098 16.1099 11.3098C15.0199 10.2198 13.0799 8.26975 11.9799 7.14975Z")
                .fill(.white)
        }
    }
}

private struct AnswerHeaderActionButton: View {
    let accessibilityLabel: String
    let action: () -> Void
    let label: () -> AnyView

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            label()
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(isHovered ? .white.opacity(0.16) : .white.opacity(0.08))
                )
                .overlay(
                    Circle()
                        .strokeBorder(.white.opacity(isHovered ? 0.18 : 0), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .help(accessibilityLabel)
    }
}

extension AnswerHeaderActionButton {
    init<Label: View>(
        accessibilityLabel: String,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.accessibilityLabel = accessibilityLabel
        self.action = action
        self.label = { AnyView(label()) }
    }
}

private struct SVGPathShape: Shape {
    let pathData: String
    let viewport: CGSize

    func path(in rect: CGRect) -> Path {
        let path = SVGPathCache.path(for: pathData)
        let transform = CGAffineTransform(
            scaleX: rect.width / max(viewport.width, 1),
            y: rect.height / max(viewport.height, 1)
        )
        return path.applying(transform)
    }

    init(pathData: String, viewport: CGSize = CGSize(width: 24, height: 24)) {
        self.pathData = pathData
        self.viewport = viewport
    }
}

private enum SVGPathCache {
    private static let lock = NSLock()
    private static var storage: [String: Path] = [:]

    static func path(for pathData: String) -> Path {
        lock.lock()
        if let cached = storage[pathData] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        var parser = SVGPathParser(pathData: pathData)
        let parsed = parser.parse()

        lock.lock()
        storage[pathData] = parsed
        lock.unlock()
        return parsed
    }
}

private struct SVGPathParser {
    let pathData: String
    private let separators = CharacterSet(charactersIn: " ,\n\t")

    private var characters: [Character] { Array(pathData) }
    private var index = 0

    init(pathData: String) {
        self.pathData = pathData
    }

    mutating func parse() -> Path {
        var path = Path()
        var command: Character?
        var currentPoint = CGPoint.zero
        var subpathStart = CGPoint.zero

        while true {
            skipSeparators()
            guard index < characters.count else { break }

            if let nextCommand = currentCommandCharacter() {
                command = nextCommand
                index += 1
            }

            guard let command else { break }

            switch command {
            case "M":
                guard let point = readPoint() else { break }
                path.move(to: point)
                currentPoint = point
                subpathStart = point

                while let point = readPoint() {
                    path.addLine(to: point)
                    currentPoint = point
                }
            case "L":
                while let point = readPoint() {
                    path.addLine(to: point)
                    currentPoint = point
                }
            case "C":
                while let control1 = readPoint(),
                      let control2 = readPoint(),
                      let point = readPoint() {
                    path.addCurve(to: point, control1: control1, control2: control2)
                    currentPoint = point
                }
            case "H":
                while let x = readNumber() {
                    currentPoint = CGPoint(x: x, y: currentPoint.y)
                    path.addLine(to: currentPoint)
                }
            case "V":
                while let y = readNumber() {
                    currentPoint = CGPoint(x: currentPoint.x, y: y)
                    path.addLine(to: currentPoint)
                }
            case "Z", "z":
                path.closeSubpath()
                currentPoint = subpathStart
            default:
                index += 1
            }
        }

        return path
    }

    private mutating func currentCommandCharacter() -> Character? {
        guard index < characters.count else { return nil }
        let character = characters[index]
        return character.isLetter ? character : nil
    }

    private mutating func skipSeparators() {
        while index < characters.count {
            let scalar = String(characters[index]).unicodeScalars.first
            if let scalar, separators.contains(scalar) {
                index += 1
            } else {
                break
            }
        }
    }

    private mutating func readPoint() -> CGPoint? {
        let startIndex = index
        guard let x = readNumber() else {
            index = startIndex
            return nil
        }
        guard let y = readNumber() else {
            index = startIndex
            return nil
        }
        return CGPoint(x: x, y: y)
    }

    private mutating func readNumber() -> CGFloat? {
        skipSeparators()
        guard index < characters.count else { return nil }

        let start = index
        var hasDigit = false

        if characters[index] == "-" || characters[index] == "+" {
            index += 1
        }

        while index < characters.count, characters[index].isNumber {
            hasDigit = true
            index += 1
        }

        if index < characters.count, characters[index] == "." {
            index += 1
            while index < characters.count, characters[index].isNumber {
                hasDigit = true
                index += 1
            }
        }

        guard hasDigit else {
            index = start
            return nil
        }

        let numberString = String(characters[start..<index])
        return CGFloat(Double(numberString) ?? 0)
    }
}
