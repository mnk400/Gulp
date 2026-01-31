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

    // Completed state (persists across view switches)
    var showCompleted: Bool = false
    var completedRunId: UUID?

    // Retry/auto-start trigger
    var shouldAutoStart: Bool = false

    func resetDownloadState() {
        isDownloading = false
        currentFile = ""
        downloadedCount = 0
        skippedCount = 0
        errorMessage = nil
        lastActivityTime = nil
    }
}
