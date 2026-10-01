//
//  DownloadRun.swift
//  Gulp
//

import Foundation

enum RunStatus: String, Codable {
    case inProgress
    case completed
    case failed
    case cancelled
}

enum LogType: String, Codable {
    case info
    case download
    case skip
    case error
    case warning
}

struct LogEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let message: String
    let type: LogType

    init(message: String, type: LogType = .info) {
        self.id = UUID()
        self.timestamp = Date()
        self.message = message
        self.type = type
    }
}

struct DownloadRun: Identifiable, Codable {
    let id: UUID
    let url: String
    let timestamp: Date
    let outputDirectory: String
    var status: RunStatus
    var fileCount: Int
    var logs: [LogEntry]

    /// Total bytes written by this run. Optional so history recorded before sizes were
    /// tracked still decodes — synthesized Codable skips missing keys for optionals,
    /// which is why this needs no schema version bump.
    var totalBytes: Int64?

    init(url: String, outputDirectory: String) {
        self.id = UUID()
        self.url = url
        self.timestamp = Date()
        self.outputDirectory = outputDirectory
        self.status = .inProgress
        self.fileCount = 0
        self.logs = []
    }

    mutating func addLog(_ message: String, type: LogType = .info) {
        logs.append(LogEntry(message: message, type: type))
    }

    var displayName: String {
        // Just show the domain name
        guard let urlObj = URL(string: url),
              let host = urlObj.host else { return url }

        // Remove "www." prefix if present
        let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return domain
    }

    var faviconDomain: String {
        // Return full host for favicon API (including www.)
        guard let urlObj = URL(string: url),
              let host = urlObj.host else { return "" }
        return host
    }

    /// The name of what was downloaded, taken from the folder gallery-dl actually wrote to.
    /// Falls back to the URL when the run produced no folder of its own — `actualDownloadDirectory`
    /// returns `outputDirectory` for runs that wrote nothing, which would otherwise title every
    /// failed run after the base directory.
    ///
    /// No attempt is made to tell an opaque ID from a real name: there is no syntactic difference
    /// between the two (`nasa` and `x8Kd2` are both plausible usernames), so any heuristic
    /// mislabels real data in both directions. A bare ID is never worse than showing the domain.
    var title: String {
        let directory = actualDownloadDirectory
        guard directory != outputDirectory else { return bareURL }
        return URL(fileURLWithPath: directory).lastPathComponent
    }

    /// The URL without the parts every link shares, so a fallback title spends its
    /// width on what tells runs apart.
    private var bareURL: String {
        var bare = url
        for prefix in ["https://", "http://", "www."] where bare.hasPrefix(prefix) {
            bare.removeFirst(prefix.count)
        }
        return bare.hasSuffix("/") ? String(bare.dropLast()) : bare
    }

    /// Files that were already on disk. Counted from the logs because only the
    /// combined `fileCount` is stored.
    var skippedCount: Int {
        logs.lazy.filter { $0.type == .skip }.count
    }

    /// One readable line explaining a failure. gallery-dl's own error lines carry
    /// `[extractor][error]` prefixes that say nothing to the reader, and the runner's
    /// fallback only has an exit code, which gallery-dl defines as a bitmask.
    var failureSummary: String {
        guard let message = logs.last(where: { $0.type == .error })?.message else {
            return "Download failed"
        }

        let exitPrefix = "Download failed with exit code "
        if message.hasPrefix(exitPrefix), let code = Int(message.dropFirst(exitPrefix.count)) {
            return Self.describe(exitCode: code)
        }

        var text = Substring(message)
        while text.hasPrefix("["), let close = text.firstIndex(of: "]") {
            text = text[text.index(after: close)...].drop(while: \.isWhitespace)
        }
        if let http = Self.describe(httpError: text) { return http }
        return text.isEmpty ? message : String(text)
    }

    /// gallery-dl reports HTTP failures as `HttpError: '403 Forbidden' for 'https://…'`.
    /// The status is the useful part; the API URL after it means nothing to the reader.
    private static func describe(httpError text: Substring) -> String? {
        guard text.hasPrefix("HttpError: '"),
              let status = text.dropFirst("HttpError: '".count).split(separator: "'").first,
              let code = Int(status.prefix(3)) else { return nil }
        switch code {
        case 401, 403: return "\(status) — this site may need you to log in"
        case 404, 410: return "\(status) — the page may have been removed"
        case 429: return "\(status) — too many requests, try again later"
        default: return "\(status) from the site"
        }
    }

    /// Exit status bits from gallery-dl's `exception.py`, most specific first.
    private static func describe(exitCode code: Int) -> String {
        let reasons: [(bit: Int, text: String)] = [
            (64, "Unsupported link — no gallery-dl extractor matches it"),
            (16, "Login required — gallery-dl needs credentials for this site"),
            (8, "Not found — the page may have been removed"),
            (4, "The site returned an HTTP error"),
            (32, "Output format error in the gallery-dl config"),
            (128, "Couldn't write to the destination folder"),
        ]
        return reasons.first { code & $0.bit != 0 }?.text ?? "gallery-dl exited with code \(code)"
    }

    /// Formatted total size, or nil for runs recorded before sizes were tracked.
    var sizeText: String? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    var statusColor: String {
        switch status {
        case .inProgress: return "yellow"
        case .completed: return "green"
        case .failed: return "red"
        case .cancelled: return "gray"
        }
    }

    /// Determines the actual directory where files were downloaded by parsing log entries.
    /// Returns the deepest common directory from file paths in the logs, or falls back to outputDirectory.
    var actualDownloadDirectory: String {
        // Find all download/skip log entries that contain file paths
        // Skip lines are logged as gallery-dl prints them, `# /path`. Left on, the
        // prefix makes a relative path that shares only `/` with real downloads.
        let downloadPaths = logs
            .filter { $0.type == .download || $0.type == .skip }
            .map { $0.message.hasPrefix("# ") ? String($0.message.dropFirst(2)) : $0.message }

        guard !downloadPaths.isEmpty else {
            return outputDirectory
        }

        // Extract directory paths (remove filename)
        let directories = downloadPaths.compactMap { path -> String? in
            let url = URL(fileURLWithPath: path)
            return url.deletingLastPathComponent().path
        }

        guard !directories.isEmpty else {
            return outputDirectory
        }

        // Find the deepest common directory
        // Start with the first directory and find the longest common path
        var commonPath = directories[0]

        for dir in directories.dropFirst() {
            while !dir.hasPrefix(commonPath) && !commonPath.isEmpty {
                // Go up one directory level
                let url = URL(fileURLWithPath: commonPath)
                commonPath = url.deletingLastPathComponent().path
            }
        }

        // If we found a common path that's more specific than the base output directory, use it
        // Otherwise fall back to the base output directory
        return commonPath.isEmpty ? outputDirectory : commonPath
    }
}
