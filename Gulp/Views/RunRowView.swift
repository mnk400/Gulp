//
//  RunRowView.swift
//  Gulp
//
//  One row per run. Settled rows are two lines; the active run grows a third
//  for its current file and shrinks back the moment it finishes.
//

import SwiftUI
import AppKit

/// Live values for the active run, pulled from `UIState`. Nil for settled rows.
struct LiveStats {
    let fileCount: Int
    let skippedCount: Int
    let sizeText: String?
    /// Nil until bytes have actually moved, so the row never claims "Zero KB/s".
    let rateText: String?
    let currentFile: String
    let stallMessage: String?

    /// Downloaded plus skipped, the same total a settled row shows, so the count
    /// doesn't jump when the run finishes — and a re-run that skips everything
    /// still visibly progresses instead of reading "starting" throughout.
    var totalCount: Int { fileCount + skippedCount }
}

struct RunRowView: View {
    let run: DownloadRun
    let live: LiveStats?
    let isSelected: Bool
    let isFocused: Bool
    let isLogExpanded: Bool
    let onToggleLog: () -> Void
    let onRetry: () -> Void
    let onStop: () -> Void
    let onSelect: () -> Void
    let onOpen: () -> Void

    @State private var isHovered = false
    @Environment(\.appearsActive) private var appearsActive

    private var isFailed: Bool { run.status == .failed }

    /// A focused selection in a key window is drawn in the system's selection
    /// colour, and every tint in the row gives way to white on it, as in Finder
    /// and Mail.
    private var isEmphasized: Bool { isSelected && isFocused && appearsActive }

    private let cornerRadius: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .contentShape(Rectangle())
                .onTapGesture {
                    onSelect()
                    // Reads the click count instead of adding a double-tap gesture,
                    // which would delay every single click. It covers only the
                    // row's own lines, so double-clicks in the log (selecting text)
                    // or on its buttons never open Finder.
                    if NSApp.currentEvent?.clickCount == 2 { onOpen() }
                }

            if isFailed && isLogExpanded {
                logBlock
                    // Aligned under the title: favicon width plus the gap.
                    .padding(.leading, 26)
                    .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(backgroundFill)
        }
        .modifier(ActiveGlass(isActive: live != nil, cornerRadius: cornerRadius))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        // Retry and Log only appear under the pointer, which assistive tech
        // never provides, so they're offered as actions on the row itself.
        .accessibilityElement(children: .combine)
        .accessibilityActions {
            if isFailed {
                Button("Retry", action: onRetry)
                Button(isLogExpanded ? "Hide Log" : "Show Log", action: onToggleLog)
            }
            if live != nil {
                Button("Stop Download", action: onStop)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            FaviconView(domain: run.faviconDomain, isOnSelection: isEmphasized)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(run.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isEmphasized ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(run.url)

                    Spacer(minLength: 0)

                    trailing
                }

                subtitle

                if let live, live.stallMessage == nil, !live.currentFile.isEmpty {
                    Text("↓ \(live.currentFile)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(meta)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .contentTransition(.opacity)
                        .transition(.opacity)
                }
            }
        }
    }

    private var backgroundFill: Color {
        if isEmphasized { return Color(nsColor: .selectedContentBackgroundColor) }
        // The system's unemphasized gray is opaque and made for flat tables; on
        // the window's material it reads as a slab, so this tints with it instead.
        if isSelected { return .primary.opacity(0.08) }
        if isHovered { return .primary.opacity(0.045) }
        return .clear
    }

    // MARK: - Styles that yield to the selection

    private var meta: AnyShapeStyle {
        isEmphasized ? AnyShapeStyle(.white.opacity(0.72)) : AnyShapeStyle(.tertiary)
    }

    private var numbers: AnyShapeStyle {
        isEmphasized ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary)
    }

    private func tint(_ color: Color) -> Color {
        isEmphasized ? .white : color
    }

    // MARK: - Line 1 trailing

    @ViewBuilder
    private var trailing: some View {
        if isFailed {
            failedTrailing
        } else if let live {
            HStack(spacing: 8) {
                if live.totalCount > 0 {
                    counts(live.totalCount, size: live.sizeText)
                }
                Button(action: onStop) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(numbers)
                        .frame(width: 18, height: 18)
                        .contentShape(Circle().inset(by: -6))
                }
                .buttonStyle(PressableButtonStyle())
                .help("Stop download (⌘.)")
                .accessibilityLabel("Stop download")
            }
        } else if run.fileCount == 0 {
            // gallery-dl can finish cleanly having found nothing to save.
            Text(run.status == .cancelled ? "Cancelled" : "Nothing found")
                .font(.system(size: 12))
                .foregroundStyle(meta)
        } else {
            counts(run.fileCount, size: run.sizeText)
        }
    }

    /// gallery-dl fails a whole run over a single file, so a failure that still
    /// saved most of a gallery leads with what landed.
    @ViewBuilder
    private var failedTrailing: some View {
        let failed = run.failedFileCount
        let label = failed > 0 ? "\(failed) failed" : "Failed"
        if run.fileCount > 0 {
            Text("\(fileLabel(run.fileCount)) · \(Text(label).foregroundStyle(tint(.red)).fontWeight(.medium))")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(numbers)
        } else {
            Text("Failed")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint(.red))
        }
    }

    private func counts(_ count: Int, size: String?) -> some View {
        Text(size.map { "\(fileLabel(count)) · \($0)" } ?? fileLabel(count))
            .font(.system(size: 12))
            .monospacedDigit()
            .foregroundStyle(numbers)
            .contentTransition(.numericText(value: Double(count)))
            .animation(.snappy(duration: 0.25), value: count)
    }

    private func fileLabel(_ n: Int) -> String {
        n == 1 ? "1 file" : "\(n) files"
    }

    // MARK: - Line 2

    @ViewBuilder
    private var subtitle: some View {
        if let live {
            liveSubtitle(live)
        } else if isFailed {
            failedSubtitle
        } else {
            // Relative times go stale while the window sits open, so they tick.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(settledSubtitle(now: context.date))
                    .font(.system(size: 12))
                    .foregroundStyle(meta)
                    .lineLimit(1)
            }
        }
    }

    private func liveSubtitle(_ live: LiveStats) -> some View {
        let state: (text: String, color: Color) = {
            if let stall = live.stallMessage { return (stall, .orange) }
            if live.totalCount == 0 && live.currentFile.isEmpty { return ("starting", .accentColor) }
            return ("downloading", .accentColor)
        }()
        let rate = live.stallMessage == nil ? live.rateText.map { " · \($0)" } ?? "" : ""

        return HStack(spacing: 6) {
            PulseDot(color: tint(state.color))
            Text("\(run.displayName) · \(Text(state.text).foregroundStyle(tint(state.color)).fontWeight(.medium))\(rate)")
                .foregroundStyle(meta)
                .monospacedDigit()
        }
        .font(.system(size: 12))
        .lineLimit(1)
    }

    private var failedSubtitle: some View {
        // Actions stay out of the way until the row is pointed at, so a list with
        // a few failures doesn't turn into a column of blue links.
        let showsActions = isHovered || isSelected || isLogExpanded

        return HStack(spacing: 12) {
            Text(run.failureSummary)
                .foregroundStyle(isEmphasized ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.red.opacity(0.9)))
                .lineLimit(1)
                .truncationMode(.tail)
                .help(run.failureSummary)

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                Button("Retry", action: onRetry)
                Button(isLogExpanded ? "Hide Log" : "Log", action: onToggleLog)
            }
            .buttonStyle(PressableButtonStyle())
            .fontWeight(.medium)
            .foregroundStyle(tint(.accentColor))
            .opacity(showsActions ? 1 : 0)
            .allowsHitTesting(showsActions)
        }
        .font(.system(size: 12))
    }

    private func settledSubtitle(now: Date) -> String {
        let age = now.timeIntervalSince(run.timestamp)
        let when = age < 60 ? "just now" : run.timestamp.formatted(.relative(presentation: .numeric))

        var parts = [run.displayName, when]
        let skipped = run.skippedCount
        if skipped > 0 { parts.append("\(skipped) skipped") }
        // A cancelled run with nothing saved already says so on the right.
        if run.status == .cancelled && run.fileCount > 0 { parts.append("cancelled") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Inline log (failed runs only)

    private var logBlock: some View {
        VStack(alignment: .leading, spacing: 9) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(run.logs) { entry in
                        Text("\(Text(entry.timestamp, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute().second()).foregroundStyle(.tertiary))  \(Text(entry.message).foregroundStyle(logColor(entry.type)))")
                            .font(.system(size: 10.5, design: .monospaced))
                            .lineSpacing(2)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 132)
            .background(.background.opacity(0.35), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
            }

            // Most failures are authentication, not bugs, so the row points at the
            // three things that actually resolve them — phrased conditionally,
            // since this sits under every failure, dropped connections included.
            Text("If this site needs a login, gallery-dl may need cookies, an OAuth token, or credentials in its config.")
                .font(.system(size: 11))
                .foregroundStyle(meta)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 14) {
                Button("Open Config") { ConfigManager.openInEditor() }
                Button("Configuration Guide") {
                    open("https://github.com/mikf/gallery-dl/blob/master/docs/configuration.rst")
                }
                Button("Supported Sites") {
                    open("https://github.com/mikf/gallery-dl/blob/master/docs/supportedsites.md")
                }
            }
            .font(.system(size: 11, weight: .medium))
            .buttonStyle(PressableButtonStyle())
            .foregroundStyle(tint(.accentColor))
        }
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    private func logColor(_ type: LogType) -> Color {
        switch type {
        case .error: return .red
        case .warning: return .orange
        case .download: return .primary
        default: return .secondary
        }
    }
}


/// Only the run that's actually running is made of glass; settled rows are flat.
/// The effect marks what's alive rather than decorating the list.
struct ActiveGlass: ViewModifier {
    let isActive: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if isActive {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
        }
    }
}
