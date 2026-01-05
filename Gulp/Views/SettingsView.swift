//
//  SettingsView.swift
//  Gulp
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(UserSettings.self) private var settings
    @AppStorage("skipExisting") private var skipExisting = true
    @AppStorage("saveMetadata") private var saveMetadata = false
    @AppStorage("showNotifications") private var showNotifications = true
    @AppStorage("outputDirectory") private var outputDirectoryPath = ""
    @AppStorage("useCustomConfig") private var useCustomConfig = false
    @State private var configRefreshTrigger = false

    private var displayPath: String {
        if outputDirectoryPath.isEmpty {
            return "~/Downloads"
        }
        return outputDirectoryPath.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private var customConfigDisplayPath: String {
        // configRefreshTrigger forces SwiftUI to re-evaluate this when file changes
        _ = configRefreshTrigger
        guard let url = settings.customConfigURL else { return "No file selected" }
        return url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private var customConfigExists: Bool {
        _ = configRefreshTrigger
        guard let url = settings.customConfigURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Save to") {
                    HStack {
                        Text(displayPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Button("Browse...") {
                            browseForFolder()
                        }
                    }
                }
            } header: {
                Text("Downloads")
            }

            Section {
                Toggle("Skip existing files", isOn: $skipExisting)
                Toggle("Save metadata", isOn: $saveMetadata)
                Toggle("Show notifications on completion", isOn: $showNotifications)
            } header: {
                Text("Options")
            }

            Section {
                Picker("Configuration", selection: $useCustomConfig) {
                    Text("App-managed").tag(false)
                    Text("Custom config file").tag(true)
                }
                .pickerStyle(.radioGroup)

                if useCustomConfig {
                    LabeledContent("Config file") {
                        HStack {
                            if settings.customConfigURL != nil {
                                if customConfigExists {
                                    Text(customConfigDisplayPath)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                } else {
                                    Label("File not found", systemImage: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                }
                            } else {
                                Text("No file selected")
                                    .foregroundStyle(.secondary)
                            }

                            Button("Browse...") {
                                browseForConfig()
                            }
                        }
                    }
                }

                Button {
                    ConfigManager.openInEditor(settings: settings)
                } label: {
                    HStack {
                        Image(systemName: "doc.text")
                        Text("Edit Config File...")
                    }
                }
                .help("Opens the \(useCustomConfig ? "custom" : "app-managed") config file in your default editor")

                Text("Advanced settings like authentication, rate limits, and site-specific options can be configured in the config file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Advanced Configuration")
            }

            Section {
                LabeledContent("gallery-dl") {
                    if let path = GalleryDLRunner.findExecutable() {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Installed")
                                .foregroundStyle(.secondary)
                        }
                        .help(path)
                    } else {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                            Text("Not found")
                                .foregroundStyle(.secondary)
                        }
                        .help("Install with: brew install gallery-dl")
                    }
                }

                if GalleryDLRunner.findExecutable() == nil {
                    Text("Install gallery-dl using Homebrew:\nbrew install gallery-dl")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Status")
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize()
    }

    private func browseForFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = "Choose where to save downloads"

        if !outputDirectoryPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: outputDirectoryPath)
        } else {
            panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        }

        if panel.runModal() == .OK, let url = panel.url {
            outputDirectoryPath = url.path
        }
    }

    private func browseForConfig() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.message = "Choose a gallery-dl config file"

        // Start in common config locations
        if let configDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .deletingLastPathComponent()
            .appendingPathComponent(".config") {
            panel.directoryURL = configDir
        }

        if panel.runModal() == .OK, let url = panel.url {
            // Create security-scoped bookmark for sandbox
            if let bookmark = try? url.bookmarkData(options: .withSecurityScope) {
                settings.customConfigBookmark = bookmark
                configRefreshTrigger.toggle()
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(UserSettings())
}
