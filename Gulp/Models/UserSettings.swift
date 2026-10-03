//
//  UserSettings.swift
//  Gulp
//
//  Persisted user preferences backed by UserDefaults.
//

import SwiftUI
import Foundation

/// The one place preferences live. Stored rather than computed, so views that
/// read them update when they change, and written through to UserDefaults.
@Observable
class UserSettings {
    var outputDirectory: URL {
        didSet { UserDefaults.standard.set(outputDirectory.path, forKey: "outputDirectory") }
    }

    var skipExisting: Bool {
        didSet { UserDefaults.standard.set(skipExisting, forKey: "skipExisting") }
    }

    var saveMetadata: Bool {
        didSet { UserDefaults.standard.set(saveMetadata, forKey: "saveMetadata") }
    }

    var showNotifications: Bool {
        didSet { UserDefaults.standard.set(showNotifications, forKey: "showNotifications") }
    }

    init() {
        let defaults = UserDefaults.standard
        if let saved = defaults.string(forKey: "outputDirectory"), !saved.isEmpty {
            outputDirectory = URL(fileURLWithPath: saved)
        } else {
            outputDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        }
        skipExisting = defaults.object(forKey: "skipExisting") as? Bool ?? true
        saveMetadata = defaults.object(forKey: "saveMetadata") as? Bool ?? false
        showNotifications = defaults.object(forKey: "showNotifications") as? Bool ?? true
    }
}
