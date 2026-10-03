//
//  HistoryManager.swift
//  Gulp
//

import Foundation

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
class HistoryManager {
    private(set) var runs: [DownloadRun] = []
    private let maxEntries = 100
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    static let historyURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("GalleryDL/history.json")

    init() {
        load()
        // Only one Gulp runs at a time, so nothing loaded can still be going.
        settleInterruptedRuns()
    }

    // MARK: - CRUD Operations

    func addRun(_ run: DownloadRun) {
        runs.insert(run, at: 0)
        trimIfNeeded()
        save()
    }

    /// Called for every line gallery-dl prints. Rewriting the whole history each
    /// time made long runs stutter, so these are written at most once a second.
    func updateRun(_ run: DownloadRun) {
        guard let index = runs.firstIndex(where: { $0.id == run.id }) else { return }
        runs[index] = run
        guard pendingSave == nil else { return }
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    /// Writes any update still waiting on the once-a-second save.
    func flush() {
        if pendingSave != nil { save() }
    }

    func deleteRun(_ run: DownloadRun) {
        runs.removeAll { $0.id == run.id }
        save()
    }

    /// A run still marked in progress when nothing is running was cut off by a
    /// quit or a crash. Its count is only stored when it finishes, so it's
    /// recovered from the logs, which are saved as files land.
    func settleInterruptedRuns() {
        guard runs.contains(where: { $0.status == .inProgress }) else { return }
        for index in runs.indices where runs[index].status == .inProgress {
            runs[index].status = .cancelled
            runs[index].fileCount = runs[index].logs.count { $0.type == .download || $0.type == .skip }
            runs[index].addLog("Stopped when Gulp quit", type: .warning)
        }
        save()
    }

    // MARK: - Persistence

    private func save() {
        pendingSave?.cancel()
        pendingSave = nil
        do {
            let directory = Self.historyURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }

            let historyFile = HistoryFile(runs: runs)
            let data = try JSONEncoder().encode(historyFile)
            // Atomic, so a crash mid-write leaves the previous file rather than half of one.
            try data.write(to: Self.historyURL, options: .atomic)
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
            // Starting empty would overwrite the file on the next save. Set it
            // aside instead, so the history can still be recovered by hand.
            print("Failed to load history: \(error)")
            let unreadable = Self.historyURL.deletingPathExtension()
                .appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: Self.historyURL, to: unreadable)
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
