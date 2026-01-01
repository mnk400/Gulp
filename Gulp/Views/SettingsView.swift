//
//  SettingsView.swift
//  Gulp
//

import SwiftUI
import AppKit

struct SettingsView: View {
    @AppStorage("skipExisting") private var skipExisting = true
    @AppStorage("saveMetadata") private var saveMetadata = false
    @AppStorage("showNotifications") private var showNotifications = true
    @AppStorage("outputDirectory") private var outputDirectoryPath = ""

    private var displayPath: String {
        if outputDirectoryPath.isEmpty {
            return "~/Downloads"
        }
        return outputDirectoryPath.replacingOccurrences(of: NSHomeDirectory(), with: "~")
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
                Button {
                    ConfigManager.openInEditor()
                } label: {
                    HStack {
                        Image(systemName: "doc.text")
                        Text("Edit Config File...")
                    }
                }
                .help("Opens the gallery-dl config file in your default editor")

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
}

#Preview {
    SettingsView()
}
