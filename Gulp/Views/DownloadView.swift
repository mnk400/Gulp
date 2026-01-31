//
//  DownloadView.swift
//  Gulp
//

import SwiftUI
import AppKit
import Combine

struct DownloadView: View {
    @Environment(UIState.self) private var uiState
    @Environment(UserSettings.self) private var settings
    @Environment(HistoryManager.self) private var historyManager
    @Binding var selection: NavigationItem?
    @State private var runner = GalleryDLRunner()
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var errorRunId: UUID?
    @State private var stallMessage: String?

    private let activityTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var buttonTint: Color? {
        if uiState.showCompleted {
            return Color(red: 110/255, green: 163/255, blue: 95/255)
        } else if uiState.isDownloading {
            return .red
        }
        return .accentColor
    }

    private var buttonIcon: String {
        if uiState.showCompleted {
            return "checkmark"
        } else if uiState.isDownloading {
            return "xmark"
        }
        return "arrow.down"
    }

    private var buttonText: String {
        if uiState.showCompleted {
            return "Completed!"
        } else if uiState.isDownloading {
            return "Cancel"
        }
        return "Download"
    }

    private var completedRun: DownloadRun? {
        guard let id = uiState.completedRunId else { return nil }
        return historyManager.runs.first { $0.id == id }
    }

    private var downloadedFiles: [String] {
        guard let run = completedRun else { return [] }
        return run.logs
            .filter { $0.type == .download }
            .compactMap { URL(string: $0.message)?.lastPathComponent ?? $0.message.components(separatedBy: "/").last }
    }

    var body: some View {
        @Bindable var uiState = uiState

        VStack(spacing: 20) {
            // Header
            Text("Download")
                .font(.title)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)

            // URL Input Section
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    TextField("Paste gallery or image URL...", text: $uiState.url)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(.background.tertiary)
                        .clipShape(RoundedRectangle(cornerRadius: 40))
                        .onSubmit {
                            startDownload()
                        }
                        .onChange(of: uiState.url) { _, newValue in
                            // Clear completed state when user starts typing
                            if !newValue.isEmpty && uiState.showCompleted {
                                uiState.showCompleted = false
                                uiState.completedRunId = nil
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
                if uiState.isDownloading {
                    runner.cancel()
                } else if !uiState.showCompleted {
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
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .tint(buttonTint)
            .controlSize(.large)
            .disabled(uiState.url.isEmpty && !uiState.isDownloading && !uiState.showCompleted)

            // Progress Section
            if uiState.isDownloading {
                VStack(spacing: 8) {
                    HStack {
                        Text("Downloading...")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Spacer()

                        if uiState.totalCount > 0 {
                            Text("\(uiState.downloadedCount) of \(uiState.totalCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if uiState.downloadedCount > 0 {
                            Text("\(uiState.downloadedCount) files")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    ProgressView(value: uiState.totalCount > 0 ? uiState.progress : nil)
                        .progressViewStyle(.linear)

                    if !uiState.currentFile.isEmpty {
                        Text(uiState.currentFile)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if let stallMessage {
                        Text(stallMessage)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .onReceive(activityTimer) { _ in
                    updateStallMessage()
                }
            }

            // Completed Files Section
            if uiState.showCompleted && !downloadedFiles.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Downloaded \(downloadedFiles.count) files")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.blue)

                        Spacer()

                        if let runId = uiState.completedRunId {
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
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .alert("Error", isPresented: $showError) {
            if let runId = errorRunId {
                Button("View Logs") {
                    selection = .run(runId)
                }
            }
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onChange(of: uiState.isDownloading) { _, isDownloading in
            if !isDownloading {
                stallMessage = nil
            }
        }
        .onAppear {
            updateStallMessage()
            // Check if gallery-dl is installed on first launch
            if GalleryDLRunner.findExecutable() == nil {
                errorMessage = "gallery-dl is not installed.\n\nInstall it with Homebrew:\nbrew install gallery-dl"
                showError = true
            }
            // Check if we should auto-start a download (from retry)
            if uiState.shouldAutoStart {
                uiState.shouldAutoStart = false
                startDownload()
            }
        }
    }

    private func updateStallMessage() {
        guard uiState.isDownloading,
              let last = uiState.lastActivityTime else {
            stallMessage = nil
            return
        }
        let elapsed = Date().timeIntervalSince(last)
        if elapsed > 30 {
            stallMessage = "Still waiting... gallery-dl may be retrying or the server is slow"
        } else if elapsed > 10 {
            stallMessage = "Waiting for response..."
        } else {
            stallMessage = nil
        }
    }

    private func pasteFromClipboard() {
        if let string = NSPasteboard.general.string(forType: .string) {
            uiState.url = string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func startDownload() {
        guard !uiState.url.isEmpty else { return }

        // Clear any previous completed state
        uiState.showCompleted = false
        uiState.completedRunId = nil

        Task {
            do {
                try await runner.run(url: uiState.url, outputDir: settings.outputDirectory, uiState: uiState, settings: settings, historyManager: historyManager)
                // Show completed state and store the run ID
                uiState.completedRunId = historyManager.runs.first?.id
                uiState.showCompleted = true
                uiState.url = ""
            } catch GalleryDLError.cancelled {
                // User cancelled, no error needed
            } catch {
                // Store the run ID for the "View Logs" button
                errorRunId = historyManager.runs.first?.id
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

#Preview {
    DownloadView(selection: .constant(.download))
        .environment(UIState())
        .environment(UserSettings())
        .environment(HistoryManager())
}
