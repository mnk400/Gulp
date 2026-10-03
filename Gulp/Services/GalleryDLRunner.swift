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
    private var pipes: [Pipe] = []
    private var readTasks: [Task<Void, any Error>] = []
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

    /// Everything that can stop a download before it has a row to report on, so
    /// the caller can check it while the link is still in the field.
    @discardableResult
    static func preflight(outputDir: URL) throws -> String {
        guard let path = findExecutable() else { throw GalleryDLError.notInstalled }
        do {
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        } catch {
            throw GalleryDLError.processError("Gulp can't use the download folder. \(error.localizedDescription)")
        }
        return path
    }

    func run(url: String, outputDir: URL, uiState: UIState, settings: UserSettings, historyManager: HistoryManaging) async throws {
        let executablePath = try Self.preflight(outputDir: outputDir)
        ConfigManager.ensureConfigExists()

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

        // Skipping files already on disk is gallery-dl's default, so only turning
        // it off needs a flag. (`--no-skip` also disables any download archive.)
        if !settings.skipExisting {
            arguments.append("--no-skip")
        }

        if settings.saveMetadata {
            arguments.append("--write-metadata")
        }

        arguments.append("--no-input")
        arguments.append(url)
        process.arguments = arguments

        process.qualityOfService = .userInitiated

        // gallery-dl prints file paths to stdout and log messages to stderr, so
        // reading them apart says which is which without guessing from the text.
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        self.currentProcess = process
        self.pipes = [stdout, stderr]

        // Stored so the termination handler can wait for every line before settling the run.
        readTasks = [(stdout, false), (stderr, true)].map { pipe, isLog in
            let handle = pipe.fileHandleForReading
            return Task.detached { [weak self] in
                for try await line in handle.bytes.lines {
                    await self?.handle(line: line, isLog: isLog, uiState: uiState, historyManager: historyManager)
                }
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { [weak self] proc in
                Task { @MainActor in
                    // Wait for the readers to drain all output before processing results.
                    // On cancel, the pipes' read ends are closed, which unblocks this.
                    for task in self?.readTasks ?? [] {
                        _ = try? await task.value
                    }
                    self?.readTasks = []

                    self?.currentProcess = nil
                    self?.pipes = []
                    uiState.isDownloading = false

                    // Update run status
                    if var run = self?.currentRun {
                        run.fileCount = uiState.downloadedCount + uiState.skippedCount

                        let wasCancelled = self?.isCancelling ?? false
                        self?.isCancelling = false

                        // A signal, not an exit status: gallery-dl's statuses are a
                        // bitmask, so 9 (8|1) and 15 are real failures, not kills.
                        if wasCancelled || proc.terminationReason == .uncaughtSignal {
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
                            // gallery-dl's own error is already in the log; the exit
                            // code is only worth recording when it said nothing.
                            let error = uiState.errorMessage ?? "Download failed with exit code \(proc.terminationStatus)"
                            if uiState.errorMessage == nil {
                                run.addLog(error, type: .error)
                            }
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
                for pipe in self.pipes {
                    pipe.fileHandleForWriting.closeFile()
                }
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

    var isRunning: Bool { currentProcess?.isRunning == true }

    /// Stops the download before returning, for quitting, where there's no time
    /// left for the termination handler to record the run.
    func stopNow() {
        guard let process = currentProcess, process.isRunning else { return }
        isCancelling = true
        Self.killProcessTree(rootPid: process.processIdentifier)
    }

    func cancel() {
        guard let process = currentProcess, process.isRunning else {
            print("[Cancel] No running process to cancel")
            return
        }

        let pid = process.processIdentifier
        print("[Cancel] Cancel requested for PID: \(pid)")

        isCancelling = true
        readTasks.forEach { $0.cancel() }

        // Close the pipe to ensure the reader gets EOF after the process is killed.
        // The write end may already be closed (after process.run()), but closeFile is
        // idempotent. Closing the read end breaks any blocked read() syscall.
        for pipe in pipes {
            pipe.fileHandleForWriting.closeFile()
            pipe.fileHandleForReading.closeFile()
        }
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

    /// What a line of gallery-dl's output is. On stdout that's a file it saved
    /// (`/path`) or skipped (`# /path`). On stderr the severity is only in the
    /// line's colour: piped output drops the `[error]` tag a terminal shows, so
    /// the text alone can't tell a failed download from an info message. The
    /// tag is still checked in case colour is off.
    nonisolated static func classify(_ raw: String, isLog: Bool) -> LogType {
        guard isLog else {
            if raw.hasPrefix("# ") { return .skip }
            return raw.hasPrefix("/") ? .download : .info
        }
        if raw.hasPrefix("\u{1B}["), let end = raw.firstIndex(of: "m") {
            let codes = raw[raw.index(raw.startIndex, offsetBy: 2)..<end].split(separator: ";")
            if codes.contains("31") { return .error }
            if codes.contains("33") { return .warning }
        }
        let lower = raw.lowercased()
        if lower.contains("][error]") { return .error }
        if lower.contains("][warning]") { return .warning }
        return .info
    }

    private func handle(line: String, isLog: Bool, uiState: UIState, historyManager: HistoryManaging) {
        uiState.lastActivityTime = Date()
        let trimmedLine = stripANSI(line).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLine.isEmpty else { return }
        // Log lines keep their colour for classifying; it carries the severity.
        let logType = Self.classify(isLog ? line : trimmedLine, isLog: isLog)

        // gallery-dl doesn't report file sizes, so measure what just landed on disk.
        var addedBytes: Int64 = 0
        if logType == .download {
            let attributes = try? FileManager.default.attributesOfItem(atPath: trimmedLine)
            addedBytes = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        }

        // Add to current run's logs
        if var run = currentRun {
            run.addLog(trimmedLine, type: logType)
            if addedBytes > 0 {
                run.totalBytes = (run.totalBytes ?? 0) + addedBytes
            }
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
            if addedBytes > 0 {
                uiState.recordBytes(addedBytes)
            }
        }

        // Track skipped files
        if logType == .skip {
            uiState.skippedCount += 1
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
