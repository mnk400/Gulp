//
//  UIState.swift
//  Gulp
//
//  Transient UI state that doesn't need persistence.
//

import SwiftUI
import Foundation

@Observable
class UIState {
    // Text input
    var url: String = ""

    // Download progress state
    var isDownloading: Bool = false
    var currentFile: String = ""
    var downloadedCount: Int = 0
    var skippedCount: Int = 0
    var errorMessage: String?
    var currentRunId: UUID?
    var lastActivityTime: Date?

    // Transfer stats for the active run (never persisted)
    var totalBytes: Int64 = 0
    var bytesPerSecond: Double = 0
    private var rateSamples: [(time: Date, bytes: Int64)] = []

    // Completed state (persists across view switches)
    var showCompleted: Bool = false
    var completedRunId: UUID?

    // Retry/auto-start trigger
    var shouldAutoStart: Bool = false

    /// Records bytes that just landed on disk and updates the transfer rate.
    func recordBytes(_ bytes: Int64) {
        totalBytes += bytes

        let now = Date()
        rateSamples.append((now, totalBytes))

        // Keep a ~5s window so the rate reflects recent throughput rather than the run
        // average, but never drop below two samples or slow transfers read as zero.
        while rateSamples.count > 2, now.timeIntervalSince(rateSamples[0].time) > 5 {
            rateSamples.removeFirst()
        }

        if let oldest = rateSamples.first {
            let elapsed = now.timeIntervalSince(oldest.time)
            bytesPerSecond = elapsed > 0.2 ? Double(totalBytes - oldest.bytes) / elapsed : 0
        }
    }

    var rateText: String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file) + "/s"
    }

    func resetDownloadState() {
        isDownloading = false
        currentFile = ""
        downloadedCount = 0
        skippedCount = 0
        errorMessage = nil
        lastActivityTime = nil
        totalBytes = 0
        bytesPerSecond = 0
        rateSamples.removeAll()
    }
}
