import SwiftUI

struct WaveformView: View {
    var audioLevel: Float
    var isRecording: Bool
    var transcribedText: String
    var statusMessage: String = ""
    var isEnhancing: Bool = false
    var isCompleting: Bool = false

    // Number of bars in the waveform
    private let barCount = 16
    @State private var phases: [Double] = (0..<16).map { Double($0) * 0.4 }
    @State private var animTimer: Timer?
    @State private var appeared = false
    @State private var textScrollID = UUID()
    @State private var spinAngle: Double = 0

    /// Whether we have text to show (drives expansion)
    private var displayText: String {
        let message = statusMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !message.isEmpty { return message }
        return transcribedText
    }

    private var hasText: Bool { !displayText.isEmpty }

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
                        .transition(.opacity)
                } else if isEnhancing {
                    processingSpinner
                } else {
                    Image("voxt")
                        .resizable()
                        .renderingMode(.template)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
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
            .animation(.easeInOut(duration: 0.25), value: isEnhancing)

            // Keep text visible during LLM processing to avoid layout flicker.
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
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(textScrollID, anchor: .trailing)
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
        }
        .onDisappear {
            stopAnimating()
            appeared = false
        }
    }

    // MARK: - Waveform bars (recording state)

    private var waveformBars: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.white)
                    .frame(width: 2.5, height: barHeight(for: index))
                    .animation(.easeInOut(duration: 0.1), value: audioLevel)
            }
        }
        .frame(height: 24)
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
        .frame(height: 24)
    }

    // MARK: - Processing spinner

    private var processingSpinner: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .frame(width: 14, height: 14)
            .rotationEffect(.degrees(spinAngle))
            .onAppear {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    spinAngle = 360
                }
            }
    }

    // MARK: - Bar helpers

    private func barHeight(for index: Int) -> CGFloat {
        let level = CGFloat(audioLevel)
        let phase = phases[index]
        let sine = (sin(phase) + 1) / 2
        let minH: CGFloat = 3
        let maxH: CGFloat = 22

        if isRecording {
            let driven = minH + (maxH - minH) * level * CGFloat(sine * 0.7 + 0.3)
            return max(minH, driven)
        } else {
            return minH + (maxH * 0.15) * CGFloat(sine)
        }
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
