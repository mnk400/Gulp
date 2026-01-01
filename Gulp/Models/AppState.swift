//
//  AppState.swift
//  Gulp
//

import SwiftUI
import Foundation

@Observable
class AppState {
    var url: String = ""

    // Output directory - computed to stay in sync with @AppStorage in SettingsView
    var outputDirectory: URL {
        get {
            if let savedPath = UserDefaults.standard.string(forKey: "outputDirectory"),
               !savedPath.isEmpty {
                return URL(fileURLWithPath: savedPath)
            }
            return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        }
        set {
            UserDefaults.standard.set(newValue.path, forKey: "outputDirectory")
        }
    }

    // Download state
    var isDownloading: Bool = false
    var currentFile: String = ""
    var downloadedCount: Int = 0
    var totalCount: Int = 0
    var progress: Double = 0.0
    var errorMessage: String?

    // Settings - computed properties that read from UserDefaults to stay in sync with @AppStorage
    var skipExisting: Bool {
        get { UserDefaults.standard.object(forKey: "skipExisting") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "skipExisting") }
    }

    var saveMetadata: Bool {
        get { UserDefaults.standard.object(forKey: "saveMetadata") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "saveMetadata") }
    }

    var showNotifications: Bool {
        get { UserDefaults.standard.object(forKey: "showNotifications") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "showNotifications") }
    }

    func resetDownloadState() {
        isDownloading = false
        currentFile = ""
        downloadedCount = 0
        totalCount = 0
        progress = 0.0
        errorMessage = nil
    }
}
