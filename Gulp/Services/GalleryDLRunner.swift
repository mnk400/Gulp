//
//  GalleryDLRunner.swift
//  Gulp
//

import Foundation
import UserNotifications

// MARK: - Error Types

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

// MARK: - Protocol

@MainActor
protocol DownloadRunning {
    static func findExecutable() -> String?
    func run(url: String, outputDir: URL, uiState: UIState, settings: UserSettings, historyManager: HistoryManaging) async throws
    func cancel()
}

// MARK: - Implementation

@MainActor
class GalleryDLRunner: DownloadRunning {
    private var currentProcess: Process?
    private var outputPipe: Pipe?
    private var currentRun: DownloadRun?

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

    func run(url: String, outputDir: URL, uiState: UIState, settings: UserSettings, historyManager: HistoryManaging) async throws {
        guard let executablePath = Self.findExecutable() else {
            throw GalleryDLError.notInstalled
        }

        ConfigManager.ensureConfigExists()

        // Ensure output directory exists
        if !FileManager.default.fileExists(atPath: outputDir.path) {
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        }

        // Create a new run entry
        var run = DownloadRun(url: url, outputDirectory: outputDir.path)
        run.addLog("Starting download...", type: .info)
        historyManager.addRun(run)
        currentRun = run

        uiState.resetDownloadState()
        uiState.isDownloading = true
        uiState.currentRunId = run.id

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)

        var arguments = [
            "--config", ConfigManager.configURL.path,
            "--destination", outputDir.path
        ]

        // Add options based on settings
        if settings.skipExisting {
            arguments.append("--no-skip")
            arguments.append(contentsOf: ["--download-archive", outputDir.appendingPathComponent(".gallery-dl-archive").path])
        }

        if settings.saveMetadata {
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
                await self?.parseOutput(line: line, uiState: uiState, historyManager: historyManager)
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { [weak self] proc in
                Task { @MainActor in
                    self?.currentProcess = nil
                    self?.outputPipe = nil
                    uiState.isDownloading = false

                    // Update run status
                    if var run = self?.currentRun {
                        run.fileCount = uiState.downloadedCount

                        if proc.terminationStatus == 0 {
                            run.status = .completed
                            run.addLog("Download completed: \(uiState.downloadedCount) files", type: .info)
                            historyManager.updateRun(run)

                            if settings.showNotifications {
                                self?.sendCompletionNotification(count: uiState.downloadedCount)
                            }
                            continuation.resume()
                        } else if proc.terminationStatus == 15 || proc.terminationStatus == 9 {
                            run.status = .cancelled
                            run.addLog("Download cancelled by user", type: .warning)
                            historyManager.updateRun(run)
                            continuation.resume(throwing: GalleryDLError.cancelled)
                        } else {
                            run.status = .failed
                            let error = uiState.errorMessage ?? "Download failed with exit code \(proc.terminationStatus)"
                            run.addLog(error, type: .error)
                            historyManager.updateRun(run)
                            continuation.resume(throwing: GalleryDLError.processError(error))
                        }

                        self?.currentRun = nil
                        uiState.currentRunId = nil
                    } else {
                        if proc.terminationStatus == 0 {
                            continuation.resume()
                        } else {
                            continuation.resume(throwing: GalleryDLError.processError("Unknown error"))
                        }
                    }
                }
            }

            do {
                try process.run()
            } catch {
                uiState.isDownloading = false
                if var run = self.currentRun {
                    run.status = .failed
                    run.addLog("Failed to start: \(error.localizedDescription)", type: .error)
                    historyManager.updateRun(run)
                }
                continuation.resume(throwing: error)
            }
        }
    }

    func cancel() {
        currentProcess?.terminate()
    }

    private func parseOutput(line: String, uiState: UIState, historyManager: HistoryManaging) async {
        await MainActor.run {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else { return }

            // Add to current run's logs
            if var run = currentRun {
                let logType: LogType = {
                    if trimmedLine.lowercased().contains("error") { return .error }
                    if trimmedLine.lowercased().contains("warning") { return .warning }
                    if trimmedLine.contains("/") { return .download }
                    return .info
                }()
                run.addLog(trimmedLine, type: logType)
                currentRun = run
                historyManager.updateRun(run)
            }

            // Check for error messages
            if trimmedLine.lowercased().contains("error") || trimmedLine.lowercased().contains("failed") {
                uiState.errorMessage = trimmedLine
                return
            }

            // Try to extract filename from output
            if trimmedLine.contains("/") && !trimmedLine.hasPrefix("#") {
                let components = trimmedLine.components(separatedBy: "/")
                if let filename = components.last, !filename.isEmpty {
                    uiState.currentFile = filename.trimmingCharacters(in: .whitespacesAndNewlines)
                    uiState.downloadedCount += 1

                    if uiState.totalCount > 0 {
                        uiState.progress = Double(uiState.downloadedCount) / Double(uiState.totalCount)
                    }
                }
            }

            // Try to parse count patterns like "[1/10]"
            if let match = trimmedLine.range(of: #"\[(\d+)/(\d+)\]"#, options: .regularExpression) {
                let matchStr = String(trimmedLine[match])
                let numbers = matchStr.filter { $0.isNumber || $0 == "/" }
                let parts = numbers.split(separator: "/")
                if parts.count == 2,
                   let current = Int(parts[0]),
                   let total = Int(parts[1]) {
                    uiState.downloadedCount = current
                    uiState.totalCount = total
                    uiState.progress = Double(current) / Double(total)
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
