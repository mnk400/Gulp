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

    static let defaultConfig: [String: Any] = [
        "extractor": [
            "base-directory": "~/Downloads/Gallery-DL"
        ],
        "output": [
            "mode": "auto"
        ],
        "downloader": [
            "rate": "1M",
            "retries": 3
        ]
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
                let jsonData = try JSONSerialization.data(withJSONObject: defaultConfig, options: [.prettyPrinted, .sortedKeys])
                try jsonData.write(to: configURL)
            } catch {
                print("Failed to create default config: \(error)")
            }
        }
    }

    static func openInEditor() {
        ensureConfigExists()
        NSWorkspace.shared.open(configURL)
    }

    static func updateBaseDirectory(_ path: String) {
        ensureConfigExists()

        do {
            let data = try Data(contentsOf: configURL)
            guard var config = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            var extractor = config["extractor"] as? [String: Any] ?? [:]
            extractor["base-directory"] = path
            config["extractor"] = extractor

            let updatedData = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
            try updatedData.write(to: configURL)
        } catch {
            print("Failed to update config: \(error)")
        }
    }
}
