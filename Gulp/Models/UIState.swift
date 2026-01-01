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
    var totalCount: Int = 0
    var progress: Double = 0.0
    var errorMessage: String?
    var currentRunId: UUID?

    // Completed state (persists across view switches)
    var showCompleted: Bool = false
    var completedRunId: UUID?

    func resetDownloadState() {
        isDownloading = false
        currentFile = ""
        downloadedCount = 0
        totalCount = 0
        progress = 0.0
        errorMessage = nil
    }
}
