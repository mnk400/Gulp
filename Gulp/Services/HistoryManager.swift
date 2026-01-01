//
//  HistoryManager.swift
//  Gulp
//

import Foundation

// MARK: - Protocol

protocol HistoryManaging {
    var runs: [DownloadRun] { get }
    var groupedByDate: [(String, [DownloadRun])] { get }
    func addRun(_ run: DownloadRun)
    func updateRun(_ run: DownloadRun)
    func deleteRun(_ run: DownloadRun)
    func clearHistory()
}

// MARK: - Schema

private struct HistoryFile: Codable {
    static let currentVersion = 1

    let version: Int
    let runs: [DownloadRun]

    init(runs: [DownloadRun]) {
        self.version = Self.currentVersion
        self.runs = runs
    }
}

// MARK: - Implementation

@Observable
class HistoryManager: HistoryManaging {
    private(set) var runs: [DownloadRun] = []
    private let maxEntries = 100

    static let historyURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("GalleryDL/history.json")

    init() {
        load()
    }

    // MARK: - CRUD Operations

    func addRun(_ run: DownloadRun) {
        runs.insert(run, at: 0)
        trimIfNeeded()
        save()
    }

    func updateRun(_ run: DownloadRun) {
        if let index = runs.firstIndex(where: { $0.id == run.id }) {
            runs[index] = run
            save()
        }
    }

    func deleteRun(_ run: DownloadRun) {
        runs.removeAll { $0.id == run.id }
        save()
    }

    func clearHistory() {
        runs.removeAll()
        save()
    }

    // MARK: - Grouped Access

    var groupedByDate: [(String, [DownloadRun])] {
        let calendar = Calendar.current
        let now = Date()

        var today: [DownloadRun] = []
        var yesterday: [DownloadRun] = []
        var thisWeek: [DownloadRun] = []
        var older: [DownloadRun] = []

        for run in runs {
            if calendar.isDateInToday(run.timestamp) {
                today.append(run)
            } else if calendar.isDateInYesterday(run.timestamp) {
                yesterday.append(run)
            } else if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now),
                      run.timestamp > weekAgo {
                thisWeek.append(run)
            } else {
                older.append(run)
            }
        }

        var groups: [(String, [DownloadRun])] = []
        if !today.isEmpty { groups.append(("Today", today)) }
        if !yesterday.isEmpty { groups.append(("Yesterday", yesterday)) }
        if !thisWeek.isEmpty { groups.append(("This Week", thisWeek)) }
        if !older.isEmpty { groups.append(("Older", older)) }

        return groups
    }

    // MARK: - Persistence

    private func save() {
        do {
            let directory = Self.historyURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }

            let historyFile = HistoryFile(runs: runs)
            let data = try JSONEncoder().encode(historyFile)
            try data.write(to: Self.historyURL)
        } catch {
            print("Failed to save history: \(error)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: Self.historyURL.path) else { return }

        do {
            let data = try Data(contentsOf: Self.historyURL)

            // Try loading versioned format first
            if let historyFile = try? JSONDecoder().decode(HistoryFile.self, from: data) {
                runs = migrate(historyFile)
            } else {
                // Fall back to legacy format (plain array)
                runs = try JSONDecoder().decode([DownloadRun].self, from: data)
                save() // Re-save in new versioned format
            }
        } catch {
            print("Failed to load history: \(error)")
            runs = []
        }
    }

    private func migrate(_ file: HistoryFile) -> [DownloadRun] {
        // Handle future migrations based on version
        switch file.version {
        case 1:
            return file.runs
        default:
            // Unknown future version, try to use runs as-is
            return file.runs
        }
    }

    private func trimIfNeeded() {
        if runs.count > maxEntries {
            runs = Array(runs.prefix(maxEntries))
        }
    }
}
