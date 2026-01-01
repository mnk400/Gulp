//
//  SidebarView.swift
//  Gulp
//

import SwiftUI

enum NavigationItem: Hashable {
    case download
    case run(UUID)
}

struct SidebarView: View {
    @Environment(UIState.self) private var uiState
    @Environment(HistoryManager.self) private var historyManager
    @Environment(\.openSettings) private var openSettings
    @Binding var selection: NavigationItem?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                // Download section - always at top
                Section {
                    Label("Download", systemImage: "arrow.down.circle.fill")
                        .tag(NavigationItem.download)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

                // History section
                Section("History") {
                    if historyManager.runs.isEmpty {
                        Text("No downloads yet")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        ForEach(historyManager.groupedByDate, id: \.0) { group, runs in
                            DisclosureGroup(group) {
                                ForEach(runs) { run in
                                    RunRow(run: run, isActive: uiState.currentRunId == run.id)
                                        .tag(NavigationItem.run(run.id))
                                        .contextMenu {
                                            Button {
                                                openInFinder(run)
                                            } label: {
                                                Label("Open in Finder", systemImage: "folder")
                                            }

                                            Button {
                                                copyURL(run)
                                            } label: {
                                                Label("Copy URL", systemImage: "doc.on.doc")
                                            }

                                            Divider()

                                            Button(role: .destructive) {
                                                historyManager.deleteRun(run)
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            // Settings button at bottom
            Button {
                openSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 180)
    }

    private func openInFinder(_ run: DownloadRun) {
        let url = URL(fileURLWithPath: run.outputDirectory)
        NSWorkspace.shared.open(url)
    }

    private func copyURL(_ run: DownloadRun) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(run.url, forType: .string)
    }
}

struct RunRow: View {
    let run: DownloadRun
    let isActive: Bool

    private var displayText: String {
        if run.fileCount > 0 {
            return "\(run.displayName) - \(run.fileCount) files"
        }
        return run.displayName
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(displayText)
                .font(.callout)
                .lineLimit(1)

            Spacer()

            if isActive {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 16, height: 16)
            }
        }
    }

    private var statusColor: Color {
        switch run.status {
        case .inProgress:
            return .yellow
        case .completed:
            return .green
        case .failed:
            return .red
        case .cancelled:
            return .gray
        }
    }
}

#Preview {
    SidebarView(selection: .constant(.download))
        .environment(UIState())
        .environment(UserSettings())
        .environment(HistoryManager())
}
