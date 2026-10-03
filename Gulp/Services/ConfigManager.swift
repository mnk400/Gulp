//
//  ConfigManager.swift
//  Gulp
//

import Foundation
import AppKit

struct ConfigManager {
    static let appSupportDirectory = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("GalleryDL")

    static let configURL = appSupportDirectory.appendingPathComponent("config.json")

    /// Empty sections to fill in, since gallery-dl's own defaults already suit
    /// Gulp, and the destination is always passed on the command line.
    static let defaultConfig: [String: Any] = [
        "#": "Options: https://gdl-org.github.io/docs/configuration.html",
        "extractor": [String: Any](),
        "downloader": [String: Any]()
    ]

    static func ensureConfigExists() {
        let fileManager = FileManager.default

        // Create app support directory if needed
        if !fileManager.fileExists(atPath: appSupportDirectory.path) {
            do {
                try fileManager.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
            } catch {
                print("Failed to create config directory: \(error)")
                return
            }
        }

        // Create default config if it doesn't exist
        if !fileManager.fileExists(atPath: configURL.path) {
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: defaultConfig, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
                try jsonData.write(to: configURL)
            } catch {
                print("Failed to create default config: \(error)")
            }
        }
    }

    /// Earlier versions wrote a 1 MB/s download cap into the default config.
    /// It's removed only while it's still exactly that value, so a limit the
    /// user chose themselves stays.
    static func removeLegacyRateCap() {
        guard let data = try? Data(contentsOf: configURL),
              var config = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var downloader = config["downloader"] as? [String: Any],
              downloader["rate"] as? String == "1M" else { return }

        downloader["rate"] = nil
        config["downloader"] = downloader
        do {
            let updated = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try updated.write(to: configURL, options: .atomic)
        } catch {
            print("Failed to update config: \(error)")
        }
    }

    static func openInEditor() {
        ensureConfigExists()
        NSWorkspace.shared.open(configURL)
    }
}
