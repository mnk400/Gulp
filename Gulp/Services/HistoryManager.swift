//
//  HistoryManager.swift
//  Gulp
//

import Foundation

@Observable
class HistoryManager {
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
            // Ensure directory exists
            let directory = Self.historyURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }

            let data = try JSONEncoder().encode(runs)
            try data.write(to: Self.historyURL)
        } catch {
            print("Failed to save history: \(error)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: Self.historyURL.path) else { return }

        do {
            let data = try Data(contentsOf: Self.historyURL)
            runs = try JSONDecoder().decode([DownloadRun].self, from: data)
        } catch {
            print("Failed to load history: \(error)")
            runs = []
        }
    }

    private func trimIfNeeded() {
        if runs.count > maxEntries {
            runs = Array(runs.prefix(maxEntries))
        }
    }
}
