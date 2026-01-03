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
        // Find all download log entries that contain file paths
        let downloadPaths = logs
            .filter { $0.type == .download && $0.message.contains("/") }
            .map { $0.message }

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
