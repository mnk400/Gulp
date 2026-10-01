//
//  Styles.swift
//  Gulp
//
//  The few interaction styles shared by the feed, footer, and settings popover.
//

import SwiftUI

/// Plain text or icon buttons that still answer a press. Plain buttons give no
/// feedback at all, which makes inline actions like Retry feel dead.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }
}

/// A borderless control that shows its bounds only under the pointer, the way
/// toolbar items do. Used where a bare label wouldn't read as clickable.
struct HoverHighlightButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 6
    var fillsWidth = false

    func makeBody(configuration: Configuration) -> some View {
        HoverHighlight(configuration: configuration, cornerRadius: cornerRadius, fillsWidth: fillsWidth)
    }

    private struct HoverHighlight: View {
        let configuration: Configuration
        let cornerRadius: CGFloat
        let fillsWidth: Bool
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.primary.opacity(configuration.isPressed ? 0.12 : isHovered ? 0.07 : 0))
                }
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .animation(.snappy(duration: 0.16), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.12), value: isHovered)
                .onHover { isHovered = $0 }
        }
    }
}

/// The live run's heartbeat. Breathes rather than spins: gallery-dl never reports
/// a percentage, so nothing here should look like progress toward an end.
struct PulseDot: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .phaseAnimator(reduceMotion ? [true] : [false, true]) { dot, bright in
                dot
                    .opacity(bright ? 1 : 0.35)
                    .scaleEffect(bright ? 1 : 0.7)
            } animation: { _ in
                .easeInOut(duration: 0.75)
            }
    }
}
