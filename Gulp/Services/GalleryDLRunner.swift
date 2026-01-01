//
//  GalleryDLRunner.swift
//  Gulp
//

import Foundation
import UserNotifications

enum GalleryDLError: LocalizedError {
    case notInstalled
    case processError(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "gallery-dl is not installed. Please install it using: brew install gallery-dl"
        case .processError(let message):
            return message
        case .cancelled:
            return "Download was cancelled"
        }
    }
}

@MainActor
class GalleryDLRunner {
    private var currentProcess: Process?
    private var outputPipe: Pipe?

    static let possiblePaths = [
        "/opt/homebrew/bin/gallery-dl",
        "/usr/local/bin/gallery-dl",
        NSHomeDirectory() + "/.local/bin/gallery-dl"
    ]

    static func findExecutable() -> String? {
        for path in possiblePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    func run(url: String, outputDir: URL, state: AppState) async throws {
        guard let executablePath = Self.findExecutable() else {
            throw GalleryDLError.notInstalled
        }

        ConfigManager.ensureConfigExists()

        // Ensure output directory exists
        if !FileManager.default.fileExists(atPath: outputDir.path) {
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        }

        state.resetDownloadState()
        state.isDownloading = true

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)

        var arguments = [
            "--config", ConfigManager.configURL.path,
            "--destination", outputDir.path
        ]

        // Add options based on settings
        if state.skipExisting {
            arguments.append("--no-skip")
            arguments.append(contentsOf: ["--download-archive", outputDir.appendingPathComponent(".gallery-dl-archive").path])
        }

        if state.saveMetadata {
            arguments.append("--write-metadata")
        }

        arguments.append(url)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        self.currentProcess = process
        self.outputPipe = pipe

        // Handle output asynchronously
        let handle = pipe.fileHandleForReading

        // Read output in background
        Task.detached { [weak self] in
            for try await line in handle.bytes.lines {
                await self?.parseOutput(line: line, state: state)
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { [weak self] proc in
                Task { @MainActor in
                    self?.currentProcess = nil
                    self?.outputPipe = nil
                    state.isDownloading = false

                    if proc.terminationStatus == 0 {
                        if state.showNotifications {
                            self?.sendCompletionNotification(count: state.downloadedCount)
                        }
                        continuation.resume()
                    } else if proc.terminationStatus == 15 || proc.terminationStatus == 9 {
                        // SIGTERM or SIGKILL - user cancelled
                        continuation.resume(throwing: GalleryDLError.cancelled)
                    } else {
                        let error = state.errorMessage ?? "Download failed with exit code \(proc.terminationStatus)"
                        continuation.resume(throwing: GalleryDLError.processError(error))
                    }
                }
            }

            do {
                try process.run()
            } catch {
                state.isDownloading = false
                continuation.resume(throwing: error)
            }
        }
    }

    func cancel() {
        currentProcess?.terminate()
    }

    private func parseOutput(line: String, state: AppState) async {
        await MainActor.run {
            // gallery-dl outputs filenames being downloaded
            // Format varies but typically includes the filename

            // Check for error messages
            if line.lowercased().contains("error") || line.lowercased().contains("failed") {
                state.errorMessage = line
                return
            }

            // Try to extract filename from output
            // gallery-dl typically outputs the full path of downloaded files
            if line.contains("/") && !line.hasPrefix("#") {
                let components = line.components(separatedBy: "/")
                if let filename = components.last, !filename.isEmpty {
                    state.currentFile = filename.trimmingCharacters(in: .whitespacesAndNewlines)
                    state.downloadedCount += 1

                    // Update progress if we have a total
                    if state.totalCount > 0 {
                        state.progress = Double(state.downloadedCount) / Double(state.totalCount)
                    }
                }
            }

            // Try to parse count patterns like "[1/10]" or "1 of 10"
            if let match = line.range(of: #"\[(\d+)/(\d+)\]"#, options: .regularExpression) {
                let matchStr = String(line[match])
                let numbers = matchStr.filter { $0.isNumber || $0 == "/" }
                let parts = numbers.split(separator: "/")
                if parts.count == 2,
                   let current = Int(parts[0]),
                   let total = Int(parts[1]) {
                    state.downloadedCount = current
                    state.totalCount = total
                    state.progress = Double(current) / Double(total)
                }
            }
        }
    }

    private func sendCompletionNotification(count: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Download Complete"
        content.body = count > 0 ? "Downloaded \(count) file\(count == 1 ? "" : "s")" : "Download finished"
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
