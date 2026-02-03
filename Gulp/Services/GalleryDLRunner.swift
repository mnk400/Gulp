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
@Observable
class GalleryDLRunner: DownloadRunning {
    private var currentProcess: Process?
    private var outputPipe: Pipe?
    private var readTask: Task<Void, any Error>?
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

        isCancelling = false
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

        arguments.append("--no-input")
        arguments.append(url)
        process.arguments = arguments

        process.qualityOfService = .userInitiated

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        self.currentProcess = process
        self.outputPipe = pipe

        // Handle output asynchronously
        let handle = pipe.fileHandleForReading

        // Read output in background — store the task so we can await it before processing results
        readTask = Task.detached { [weak self] in
            for try await line in handle.bytes.lines {
                await self?.parseOutput(line: line, uiState: uiState, historyManager: historyManager)
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { [weak self] proc in
                Task { @MainActor in
                    // Wait for pipe reader to drain all output before processing results.
                    // On cancel, the pipe's read end is closed which unblocks this.
                    _ = try? await self?.readTask?.value
                    self?.readTask = nil

                    self?.currentProcess = nil
                    self?.outputPipe = nil
                    uiState.isDownloading = false

                    // Update run status
                    if var run = self?.currentRun {
                        run.fileCount = uiState.downloadedCount + uiState.skippedCount

                        let wasCancelled = self?.isCancelling ?? false
                        self?.isCancelling = false

                        if wasCancelled || proc.terminationStatus == 15 || proc.terminationStatus == 9 {
                            run.status = .cancelled
                            run.addLog("Download cancelled by user", type: .warning)
                            historyManager.updateRun(run)
                            continuation.resume(throwing: GalleryDLError.cancelled)
                        } else if proc.terminationStatus == 0 {
                            run.status = .completed
                            let downloaded = uiState.downloadedCount
                            let skipped = uiState.skippedCount
                            if skipped > 0 && downloaded == 0 {
                                run.addLog("Download completed: \(skipped) files skipped (already downloaded)", type: .info)
                            } else if skipped > 0 {
                                run.addLog("Download completed: \(downloaded) files (\(skipped) skipped)", type: .info)
                            } else {
                                run.addLog("Download completed: \(downloaded) files", type: .info)
                            }
                            historyManager.updateRun(run)

                            if settings.showNotifications {
                                self?.sendCompletionNotification(count: downloaded)
                            }
                            continuation.resume()
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
                // Close the parent's copy of the write end — only the child needs it.
                // Without this, the pipe reader won't get EOF when the child exits
                // because the parent still holds the write end open.
                pipe.fileHandleForWriting.closeFile()
                uiState.lastActivityTime = Date()
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

    private var isCancelling = false

    func cancel() {
        guard let process = currentProcess, process.isRunning else {
            print("[Cancel] No running process to cancel")
            return
        }

        let pid = process.processIdentifier
        print("[Cancel] Cancel requested for PID: \(pid)")

        isCancelling = true
        readTask?.cancel()

        // Close the pipe to ensure the reader gets EOF after the process is killed.
        // The write end may already be closed (after process.run()), but closeFile is
        // idempotent. Closing the read end breaks any blocked read() syscall.
        outputPipe?.fileHandleForWriting.closeFile()
        outputPipe?.fileHandleForReading.closeFile()
        print("[Cancel] Pipes closed")

        // Force kill the entire process tree spawned by this app
        Task.detached {
            Self.killProcessTree(rootPid: pid)
        }
    }

    /// Recursively kills a process and all its descendants with SIGKILL
    private nonisolated static func killProcessTree(rootPid: Int32) {
        print("[Cancel] Starting kill of process tree for root PID: \(rootPid)")

        // First, find all descendant PIDs
        var allPids: [Int32] = []
        findDescendants(of: rootPid, into: &allPids)

        print("[Cancel] Found \(allPids.count) descendant(s): \(allPids)")

        // Kill descendants first (children before parent ensures orphans don't escape)
        for pid in allPids.reversed() {
            let result = kill(pid, SIGKILL)
            print("[Cancel] Killed descendant PID \(pid), result: \(result == 0 ? "success" : "failed (errno: \(errno))")")
        }

        // Finally kill the root process
        let result = kill(rootPid, SIGKILL)
        print("[Cancel] Killed root PID \(rootPid), result: \(result == 0 ? "success" : "failed (errno: \(errno))")")
        print("[Cancel] Process tree kill completed")
    }

    /// Recursively finds all descendant process IDs of a given parent
    private nonisolated static func findDescendants(of parentPid: Int32, into pids: inout [Int32]) {
        print("[Cancel] Finding children of PID \(parentPid)")

        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-P", String(parentPid)]
        let pipe = Pipe()
        pgrep.standardOutput = pipe
        pgrep.standardError = FileHandle.nullDevice
        try? pgrep.run()
        pgrep.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8), !output.isEmpty else {
            print("[Cancel] No children found for PID \(parentPid)")
            return
        }

        let childPids = output.split(separator: "\n").compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
        print("[Cancel] PID \(parentPid) has children: \(childPids)")

        for childPid in childPids {
            pids.append(childPid)
            // Recursively find grandchildren
            findDescendants(of: childPid, into: &pids)
        }
    }

    private func stripANSI(_ text: String) -> String {
        // Remove ANSI escape codes (e.g., [1;33m for colors)
        text.replacingOccurrences(
            of: "\\x1B\\[[0-9;]*m",
            with: "",
            options: .regularExpression
        )
    }

    private func parseOutput(line: String, uiState: UIState, historyManager: HistoryManaging) async {
        await MainActor.run {
            uiState.lastActivityTime = Date()
            let cleanedLine = stripANSI(line)
            let trimmedLine = cleanedLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else { return }

            // Classify the line type:
            // - Starts with "/" → downloaded file path (stdout in PipeOutput mode)
            // - Starts with "# /" → skipped file path
            // - Starts with "[" and contains error → error from extractor (stderr)
            // - Starts with "[" and contains warning → warning from extractor
            // - Everything else → info
            let logType: LogType = {
                if trimmedLine.hasPrefix("/") { return .download }
                if trimmedLine.hasPrefix("# /") { return .skip }
                let lower = trimmedLine.lowercased()
                if trimmedLine.hasPrefix("[") {
                    if lower.contains("error") { return .error }
                    if lower.contains("warning") { return .warning }
                }
                return .info
            }()

            // Add to current run's logs
            if var run = currentRun {
                run.addLog(trimmedLine, type: logType)
                currentRun = run
                historyManager.updateRun(run)
            }

            // Capture error messages — only for genuine errors, keep the first one
            if logType == .error && uiState.errorMessage == nil {
                uiState.errorMessage = trimmedLine
            }

            // Track downloaded files
            if logType == .download {
                let components = trimmedLine.components(separatedBy: "/")
                if let filename = components.last, !filename.isEmpty {
                    uiState.currentFile = filename
                }
                uiState.downloadedCount += 1
            }

            // Track skipped files
            if logType == .skip {
                uiState.skippedCount += 1
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
