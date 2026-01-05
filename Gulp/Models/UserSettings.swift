//
//  UserSettings.swift
//  Gulp
//
//  Persisted user preferences backed by UserDefaults.
//

import SwiftUI
import Foundation

@Observable
class UserSettings {
    // Output directory
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

    // Download options
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

    // Config source
    var useCustomConfig: Bool {
        get { UserDefaults.standard.bool(forKey: "useCustomConfig") }
        set { UserDefaults.standard.set(newValue, forKey: "useCustomConfig") }
    }

    var customConfigBookmark: Data? {
        get { UserDefaults.standard.data(forKey: "customConfigBookmark") }
        set { UserDefaults.standard.set(newValue, forKey: "customConfigBookmark") }
    }

    /// Resolves the stored bookmark to a URL, returns nil if invalid or not set
    var customConfigURL: URL? {
        guard let bookmark = customConfigBookmark else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        // If bookmark is stale, try to refresh it
        if isStale {
            if let newBookmark = try? url.bookmarkData(options: .withSecurityScope) {
                customConfigBookmark = newBookmark
            }
        }
        return url
    }
}
