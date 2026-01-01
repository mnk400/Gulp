//
//  LogDetailView.swift
//  Gulp
//

import SwiftUI
import AppKit

struct LogDetailView: View {
    let run: DownloadRun

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(run.url)
                            .font(.headline)
                            .lineLimit(2)
                            .textSelection(.enabled)

                        HStack(spacing: 12) {
                            Label(run.timestamp.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")

                            if run.fileCount > 0 {
                                Label("\(run.fileCount) files", systemImage: "doc.fill")
                            }

                            StatusBadge(status: run.status)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        openInFinder()
                    } label: {
                        Label("Open in Finder", systemImage: "folder")
                    }
                    .buttonStyle(.glass)
                }
            }
            .padding()
            .background(.ultraThinMaterial)

            Divider()

            // Logs
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(run.logs) { entry in
                            LogEntryRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onAppear {
                    // Scroll to bottom
                    if let lastLog = run.logs.last {
                        proxy.scrollTo(lastLog.id, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private func openInFinder() {
        let url = URL(fileURLWithPath: run.outputDirectory)
        NSWorkspace.shared.open(url)
    }
}

struct StatusBadge: View {
    let status: RunStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            Text(statusText)
        }
    }

    private var statusColor: Color {
        switch status {
        case .inProgress: return .yellow
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .gray
        }
    }

    private var statusText: String {
        switch status {
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}

struct LogEntryRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .frame(width: 70, alignment: .leading)

            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(logColor)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var logColor: Color {
        switch entry.type {
        case .info: return .primary
        case .download: return .green
        case .error: return .red
        case .warning: return .orange
        }
    }
}

#Preview {
    LogDetailView(run: DownloadRun(url: "https://example.com/gallery", outputDirectory: "~/Downloads"))
}
