//
//  RunRowView.swift
//  Gulp
//
//  One row per run. Settled rows are two lines; the active run grows a third
//  for its current file and shrinks back the moment it finishes.
//

import SwiftUI

/// Live values for the active run, pulled from `UIState`. Nil for settled rows.
struct LiveStats {
    let fileCount: Int
    let skippedCount: Int
    let sizeText: String?
    let rateText: String
    let currentFile: String
    let stallMessage: String?
}

struct RunRowView: View {
    let run: DownloadRun
    let live: LiveStats?
    let isSelected: Bool
    let isFocused: Bool
    let isLogExpanded: Bool
    let onToggleLog: () -> Void
    let onRetry: () -> Void

    private var isFailed: Bool { run.status == .failed }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            FaviconView(domain: run.faviconDomain)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(run.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 0)

                    trailing
                }

                subtitle

                if let live, live.stallMessage == nil, !live.currentFile.isEmpty {
                    Text("↓ \(live.currentFile)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.top, 1)
                }

                if isFailed && isLogExpanded {
                    logBlock
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 9)
                .fill(isSelected ? Color.accentColor.opacity(isFocused ? 0.20 : 0.09) : .clear)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Line 1 trailing

    @ViewBuilder
    private var trailing: some View {
        if isFailed {
            Text("Failed")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.red)
        } else {
            let count = live?.fileCount ?? run.fileCount
            let size = live?.sizeText ?? run.sizeText
            Text(size.map { "\(fileLabel(count)) · \($0)" } ?? fileLabel(count))
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private func fileLabel(_ n: Int) -> String {
        n == 1 ? "1 file" : "\(n) files"
    }

    // MARK: - Line 2

    @ViewBuilder
    private var subtitle: some View {
        if let live {
            HStack(spacing: 5) {
                Circle()
                    .fill(live.stallMessage == nil ? Color.accentColor : .orange)
                    .frame(width: 5, height: 5)

                if let stall = live.stallMessage {
                    Text("\(run.displayName) · ")
                        .foregroundStyle(.tertiary)
                    + Text(stall)
                        .foregroundStyle(.orange)
                        .fontWeight(.medium)
                } else {
                    Text("\(run.displayName) · ")
                        .foregroundStyle(.tertiary)
                    + Text("downloading")
                        .foregroundStyle(Color.accentColor)
                        .fontWeight(.medium)
                    + Text(" · \(live.rateText)")
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.system(size: 12))
            .lineLimit(1)
        } else if isFailed {
            HStack(spacing: 12) {
                Text(failureSummary)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                Button("Retry", action: onRetry)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                Button(isLogExpanded ? "Hide log" : "Log", action: onToggleLog)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
            }
            .font(.system(size: 12))
        } else {
            Text(settledSubtitle)
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    private var settledSubtitle: String {
        var parts = [run.displayName, run.timestamp.formatted(.relative(presentation: .numeric))]
        if run.status == .cancelled { parts.append("cancelled") }
        return parts.joined(separator: " · ")
    }

    /// First error line from the run's own logs, so the row explains itself
    /// without needing a separate detail view.
    private var failureSummary: String {
        run.logs.last { $0.type == .error }?.message ?? "Download failed"
    }

    // MARK: - Inline log (failed runs only)

    private var logBlock: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(run.logs) { entry in
                    Text(entry.message)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(logColor(entry.type))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(9)
        }
        .frame(maxHeight: 132)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        .padding(.top, 6)
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
