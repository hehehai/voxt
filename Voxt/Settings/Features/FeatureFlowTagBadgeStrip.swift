// FeatureFlowTagBadgeStrip.swift
// Provides Feature Flow Tag Badge Strip for feature settings.

import SwiftUI

struct FlowTagBadgeStrip: View {
    let tags: [String]

    var body: some View {
        FlexibleTagLayout(tags: tags) { tag in
            Text(tag)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(
                    Capsule()
                        .fill(SettingsUIStyle.subtleFillColor)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(SettingsUIStyle.subtleBorderColor, lineWidth: 1)
                )
        }
    }
}

private struct FlexibleTagLayout<Content: View>: View {
    let tags: [String]
    let content: (String) -> Content

    var body: some View {
        GeometryReader { proxy in
            generateContent(in: proxy)
        }
        .frame(minHeight: 10)
    }

    private func generateContent(in proxy: GeometryProxy) -> some View {
        var width = CGFloat.zero
        var height = CGFloat.zero

        return ZStack(alignment: .topLeading) {
            ForEach(tags, id: \.self) { tag in
                content(tag)
                    .padding(.trailing, 8)
                    .padding(.bottom, 8)
                    .alignmentGuide(.leading) { dimension in
                        if abs(width - dimension.width) > proxy.size.width {
                            width = 0
                            height -= dimension.height
                        }
                        let result = width
                        width = tag == tags.last ? 0 : width - dimension.width
                        return result
                    }
                    .alignmentGuide(.top) { _ in
                        let result = height
                        if tag == tags.last {
                            height = 0
                        }
                        return result
                    }
            }
        }
    }
}
