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
        let folder = URL(fileURLWithPath: directory).lastPathComponent
        guard directory != outputDirectory else { return bareURL }
        // gallery-dl files every direct image link under one `directlink` folder,
        // which names nothing. The file's own name does, and the domain is
        // already on the line below.
        if folder == "directlink", let name = URL(string: url)?.lastPathComponent, !name.isEmpty, name != "/" {
            return name
        }
        return folder
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

    /// Files gallery-dl tried and gave up on. Each gets its own
    /// `[download] Failed to download …` line, which is how a run that saved 70
    /// of 71 files is told apart from one that never got started.
    var failedFileCount: Int {
        logs.count { $0.type == .error && Self.withoutTags($0.message).hasPrefix("Failed to download") }
    }

    /// One readable line explaining a failure. gallery-dl's own error lines carry
    /// `[extractor]` prefixes that say nothing to the reader, and the runner's
    /// fallback only has an exit code, which gallery-dl defines as a bitmask.
    var failureSummary: String {
        guard let errorIndex = logs.lastIndex(where: { $0.type == .error }) else {
            return "Download failed"
        }
        let message = logs[errorIndex].message

        let exitPrefix = "Download failed with exit code "
        if message.hasPrefix(exitPrefix), let code = Int(message.dropFirst(exitPrefix.count)) {
            return Self.describe(exitCode: code)
        }

        let text = Self.withoutTags(message)
        if let status = Self.httpStatus(in: text) { return Self.describe(status: status) }

        // This line names only the file. The reason is the downloader's warning
        // logged just before it.
        if text.hasPrefix("Failed to download") {
            let reason = logs[..<errorIndex].reversed().lazy
                .compactMap { Self.httpStatus(in: Self.withoutTags($0.message)) }
                .first
            if let reason { return Self.describe(status: reason) }
            let failed = failedFileCount
            return failed == 1 ? "A file couldn't be downloaded" : "\(failed) files couldn't be downloaded"
        }
        return text.isEmpty ? message : String(text)
    }

    private static func withoutTags(_ message: String) -> Substring {
        var text = Substring(message)
        while text.hasPrefix("["), let close = text.firstIndex(of: "]") {
            text = text[text.index(after: close)...].drop(while: \.isWhitespace)
        }
        return text
    }

    /// The quoted status in gallery-dl's HTTP lines: `HttpError: '403 Forbidden' for '…'`
    /// from extractors, and `'400 Bad Request' for '…'` from the downloader. The
    /// URL after it means nothing to the reader.
    private static func httpStatus(in text: Substring) -> Substring? {
        let quoted = text.hasPrefix("HttpError: ") ? text.dropFirst("HttpError: ".count) : text
        guard quoted.hasPrefix("'"),
              let status = quoted.dropFirst().split(separator: "'", maxSplits: 1).first,
              status.prefix(3).allSatisfy(\.isNumber) else { return nil }
        return status
    }

    private static func describe(status: Substring) -> String {
        switch Int(status.prefix(3)) {
        case 401, 403: return "\(status) — this site may need you to log in"
        case 404, 410: return "\(status) — the page may have been removed"
        case 429: return "\(status) — too many requests, try again later"
        default: return String(status)
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

    /// Every file the run saved or found already saved, in the order gallery-dl
    /// reported them. Skips are logged as gallery-dl prints them, `# /path`.
    var filePaths: [String] {
        logs.compactMap { entry in
            switch entry.type {
            case .download: entry.message
            case .skip: entry.message.hasPrefix("# ") ? String(entry.message.dropFirst(2)) : entry.message
            default: nil
            }
        }
    }

    /// The deepest folder holding all of the run's files, or the base directory
    /// when it saved none.
    var actualDownloadDirectory: String {
        let folders = filePaths.map { URL(fileURLWithPath: $0).deletingLastPathComponent().pathComponents }
        guard var common = folders.first else { return outputDirectory }
        // Compared by component, so `board1` and `board10` don't share a prefix.
        for components in folders.dropFirst() {
            common = zip(common, components).prefix { $0 == $1 }.map(\.0)
        }
        // Only the root left in common: the files have nothing in common worth naming.
        return common.count > 1 ? NSString.path(withComponents: common) : outputDirectory
    }
}
