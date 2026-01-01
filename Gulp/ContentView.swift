//
//  ContentView.swift
//  Gulp
//

import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openSettings) private var openSettings
    @State private var runner = GalleryDLRunner()
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        @Bindable var state = state

        VStack(spacing: 20) {
            // Header with title and settings
            HStack {
                Text("Gulp")
                    .font(.title)
                    .fontWeight(.bold)

                Spacer()

                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Settings")
            }

            // URL Input Section
            VStack(alignment: .leading, spacing: 8) {
                Text("URL")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                HStack(spacing: 8) {
                    TextField("Paste gallery or image URL...", text: $state.url)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            startDownload()
                        }

                    Button {
                        pasteFromClipboard()
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .help("Paste from clipboard")
                }
            }

            // Download Button
            Button {
                if state.isDownloading {
                    runner.cancel()
                } else {
                    startDownload()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: state.isDownloading ? "xmark" : "arrow.down")
                        .font(.system(size: 13, weight: .semibold))
                    Text(state.isDownloading ? "Cancel" : "Download")
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 25)
            }
            .buttonStyle(.borderedProminent)
            .tint(state.isDownloading ? .red : .accentColor)
            .clipShape(Capsule())
            .disabled(state.url.isEmpty && !state.isDownloading)

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
        }
        .padding(24)
        .frame(width: 380)
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

        Task {
            do {
                try await runner.run(url: state.url, outputDir: state.outputDirectory, state: state)
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
    ContentView()
        .environment(AppState())
}
