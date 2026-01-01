//
//  DownloadView.swift
//  Gulp
//

import SwiftUI
import AppKit

struct DownloadView: View {
    @Environment(AppState.self) private var state
    @Environment(HistoryManager.self) private var historyManager
    @Binding var selection: NavigationItem?
    @State private var runner = GalleryDLRunner()
    @State private var showError = false
    @State private var errorMessage = ""

    private var buttonTint: Color? {
        if state.showCompleted {
            return .green
        } else if state.isDownloading {
            return .red
        }
        return nil
    }

    private var buttonIcon: String {
        if state.showCompleted {
            return "checkmark"
        } else if state.isDownloading {
            return "xmark"
        }
        return "arrow.down"
    }

    private var buttonText: String {
        if state.showCompleted {
            return "Completed!"
        } else if state.isDownloading {
            return "Cancel"
        }
        return "Download"
    }

    private var completedRun: DownloadRun? {
        guard let id = state.completedRunId else { return nil }
        return historyManager.runs.first { $0.id == id }
    }

    private var downloadedFiles: [String] {
        guard let run = completedRun else { return [] }
        return run.logs
            .filter { $0.type == .download }
            .compactMap { URL(string: $0.message)?.lastPathComponent ?? $0.message.components(separatedBy: "/").last }
    }

    var body: some View {
        @Bindable var state = state

        VStack(spacing: 20) {
            // Header
            Text("Download")
                .font(.title)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)

            // URL Input Section
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    TextField("Paste gallery or image URL...", text: $state.url)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(.background.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onSubmit {
                            startDownload()
                        }
                        .onChange(of: state.url) { _, newValue in
                            // Clear completed state when user starts typing
                            if !newValue.isEmpty && state.showCompleted {
                                state.showCompleted = false
                                state.completedRunId = nil
                            }
                        }

                    Button {
                        pasteFromClipboard()
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 14))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .help("Paste from clipboard")
                }
            }

            // Download Button
            Button {
                if state.isDownloading {
                    runner.cancel()
                } else if !state.showCompleted {
                    startDownload()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: buttonIcon)
                    Text(buttonText)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 35)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(buttonTint)
            .controlSize(.large)
            .disabled(state.url.isEmpty && !state.isDownloading && !state.showCompleted)

            // Progress Section
            if state.isDownloading {
                VStack(spacing: 8) {
                    HStack {
                        Text("Downloading...")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Spacer()

                        if state.totalCount > 0 {
                            Text("\(state.downloadedCount) of \(state.totalCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if state.downloadedCount > 0 {
                            Text("\(state.downloadedCount) files")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    ProgressView(value: state.totalCount > 0 ? state.progress : nil)
                        .progressViewStyle(.linear)

                    if !state.currentFile.isEmpty {
                        Text(state.currentFile)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            // Completed Files Section
            if state.showCompleted && !downloadedFiles.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Downloaded \(downloadedFiles.count) files")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.blue)

                        Spacer()

                        if let runId = state.completedRunId {
                            Button {
                                selection = .run(runId)
                            } label: {
                                Text("View Details")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.gray)
                        }
                    }

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(downloadedFiles, id: \.self) { file in
                                Text(file)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .padding()
                .background(.background.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Spacer()
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            // Check if gallery-dl is installed on first launch
            if GalleryDLRunner.findExecutable() == nil {
                errorMessage = "gallery-dl is not installed.\n\nInstall it with Homebrew:\nbrew install gallery-dl"
                showError = true
            }
        }
    }

    private func pasteFromClipboard() {
        if let string = NSPasteboard.general.string(forType: .string) {
            state.url = string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func startDownload() {
        guard !state.url.isEmpty else { return }

        // Clear any previous completed state
        state.showCompleted = false
        state.completedRunId = nil

        Task {
            do {
                try await runner.run(url: state.url, outputDir: state.outputDirectory, state: state, historyManager: historyManager)
                // Show completed state and store the run ID
                state.completedRunId = historyManager.runs.first?.id
                state.showCompleted = true
                state.url = ""
            } catch GalleryDLError.cancelled {
                // User cancelled, no error needed
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

#Preview {
    DownloadView(selection: .constant(.download))
        .environment(AppState())
        .environment(HistoryManager())
}
