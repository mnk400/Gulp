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

            // Bottom buttons
            VStack(spacing: 0) {
                Button {
                    openSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                
                Divider()
                
                Button {
                    ConfigManager.openInEditor()
                } label: {
                    Label("Gallery-dl Config", systemImage: "doc.text")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .padding(.vertical, 4)
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

    var body: some View {
        HStack(spacing: 6) {
            FaviconView(domain: run.faviconDomain)

            Text(run.displayName)
                .font(.callout)
                .lineLimit(1)

            // Status indicators
            if isActive {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 16, height: 16)
            } else if run.status != .inProgress {
                statusBadge
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        let (text, color) = badgeContent
        Text(text)
            .font(.caption2)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color)
            .clipShape(Capsule())
    }

    private var badgeContent: (String, Color) {
        switch run.status {
        case .completed:
            let fileText = run.fileCount == 1 ? "1 file" : "\(run.fileCount) files"
            return (fileText, .secondary)
        case .failed:
            return ("Failed", .red)
        case .cancelled:
            return ("Cancelled", .secondary)
        case .inProgress:
            return ("", .clear)  // Not used, but required for exhaustive switch
        }
    }
}

#Preview {
    SidebarView(selection: .constant(.download))
        .environment(UIState())
        .environment(UserSettings())
        .environment(HistoryManager())
}
