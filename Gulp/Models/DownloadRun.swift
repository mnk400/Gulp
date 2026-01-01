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
}
