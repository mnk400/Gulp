//
//  GalleryDLRunner.swift
//  Gulp
//

import Foundation
import UserNotifications

// MARK: - Errors

/// What can stop a download before it has a row to report on.
enum GalleryDLError: LocalizedError {
    case notInstalled
    case unusableFolder(any Error)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "gallery-dl is not installed. Install it with Homebrew: brew install gallery-dl"
        case .unusableFolder(let error):
            return "Gulp can't use the download folder. \(error.localizedDescription)"
        }
    }
}

// MARK: - Implementation

@MainActor
@Observable
class GalleryDLRunner {
    private var currentProcess: Process?
    private var readers: [PipeLines] = []
    private var readTasks: [Task<Void, Never>] = []
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

    /// Everything that can stop a download before it has a row to report on.
    /// Checked before the run is created, so a failure leaves the link in the field.
    private static func preflight(outputDir: URL) throws -> String {
        guard let path = findExecutable() else { throw GalleryDLError.notInstalled }
        do {
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        } catch {
            throw GalleryDLError.unusableFolder(error)
        }
        return path
    }

    /// Starts a download and returns once gallery-dl is running; the run settles
    /// itself when gallery-dl exits. Throws only for what `preflight` checks.
    func run(url: String, outputDir: URL, uiState: UIState, settings: UserSettings, historyManager: HistoryManager) throws {
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
        readers = [PipeLines(stdout), PipeLines(stderr)]

        // Stored so the termination handler can wait for every line before settling the run.
        readTasks = zip(readers, [false, true]).map { reader, isLog in
            Task { [weak self] in
                for await line in reader.lines {
                    self?.handle(line: line, isLog: isLog, uiState: uiState, historyManager: historyManager)
                }
            }
        }

        process.terminationHandler = { [weak self] process in
            Task { @MainActor in
                await self?.finish(process, uiState: uiState, settings: settings, historyManager: historyManager)
            }
        }

        do {
            try process.run()
            // Close the parent's copy of the write ends — only the child needs them.
            // Without this, the readers never see the pipes end when the child exits.
            stdout.fileHandleForWriting.closeFile()
            stderr.fileHandleForWriting.closeFile()
            uiState.lastActivityTime = Date()
        } catch {
            // No process means no termination handler, so the run settles here.
            readers.forEach { $0.abandon() }
            readers = []
            readTasks = []
            currentProcess = nil
            currentRun = nil
            run.status = .failed
            run.addLog("Failed to start: \(error.localizedDescription)", type: .error)
            historyManager.updateRun(run)
            uiState.isDownloading = false
            uiState.currentRunId = nil
        }
    }

    /// Settles the run once gallery-dl has exited and every line it printed is read.
    private func finish(_ process: Process, uiState: UIState, settings: UserSettings, historyManager: HistoryManager) async {
        // On cancel, the readers are abandoned, which unblocks this.
        for task in readTasks {
            await task.value
        }
        readTasks = []
        readers = []
        currentProcess = nil
        uiState.isDownloading = false

        guard var run = currentRun else { return }
        currentRun = nil
        uiState.currentRunId = nil
        run.fileCount = uiState.downloadedCount + uiState.skippedCount

        // A signal, not an exit status: gallery-dl's statuses are a
        // bitmask, so 9 (8|1) and 15 are real failures, not kills.
        if isCancelling || process.terminationReason == .uncaughtSignal {
            run.status = .cancelled
            run.addLog("Download cancelled by user", type: .warning)
        } else if process.terminationStatus == 0 {
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
            if settings.showNotifications {
                sendCompletionNotification(count: downloaded)
            }
        } else {
            run.status = .failed
            // gallery-dl's own error is already in the log; the exit code is
            // only worth recording when it said nothing.
            if uiState.errorMessage == nil {
                run.addLog("Download failed with exit code \(process.terminationStatus)", type: .error)
            }
        }
        isCancelling = false
        historyManager.updateRun(run)
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
        guard let process = currentProcess, process.isRunning else { return }
        let pid = process.processIdentifier
        isCancelling = true
        // A grandchild that escapes the kill could hold the pipes open forever, so
        // the run settles without waiting for their end.
        readers.forEach { $0.abandon() }
        // The whole tree, since gallery-dl can hand work to children of its own.
        Task.detached {
            Self.killProcessTree(rootPid: pid)
        }
    }

    /// Recursively kills a process and all its descendants with SIGKILL
    private nonisolated static func killProcessTree(rootPid: Int32) {

        // First, find all descendant PIDs
        var allPids: [Int32] = []
        findDescendants(of: rootPid, into: &allPids)


        // Kill descendants first (children before parent ensures orphans don't escape)
        for pid in allPids.reversed() {
            kill(pid, SIGKILL)
        }

        // Finally kill the root process
        kill(rootPid, SIGKILL)
    }

    /// Recursively finds all descendant process IDs of a given parent
    private nonisolated static func findDescendants(of parentPid: Int32, into pids: inout [Int32]) {

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
            return
        }

        let childPids = output.split(separator: "\n").compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }

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

    private func handle(line: String, isLog: Bool, uiState: UIState, historyManager: HistoryManager) {
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

/// A pipe's output, a line at a time, as it arrives. `FileHandle.bytes` was
/// simpler, but with one reading each of gallery-dl's two pipes, a quiet stderr
/// held stdout's lines back until the run ended.
nonisolated final class PipeLines: @unchecked Sendable {
    let lines: AsyncStream<String>
    private let continuation: AsyncStream<String>.Continuation
    private let handle: FileHandle
    /// Only touched from the handle's own serial readability callbacks.
    private var buffer = Data()

    init(_ pipe: Pipe) {
        (lines, continuation) = AsyncStream.makeStream()
        handle = pipe.fileHandleForReading
        handle.readabilityHandler = { [unowned self] handle in
            receive(handle.availableData)
        }
    }

    private func receive(_ data: Data) {
        guard !data.isEmpty else {
            // End of file: whatever is left was the last line, unterminated.
            if !buffer.isEmpty {
                continuation.yield(String(decoding: buffer, as: UTF8.self))
            }
            abandon()
            return
        }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            continuation.yield(String(decoding: buffer[..<newline], as: UTF8.self))
            buffer.removeSubrange(...newline)
        }
    }

    /// Ends the lines now, without waiting for the pipe to close.
    func abandon() {
        handle.readabilityHandler = nil
        continuation.finish()
    }
}
