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
}
