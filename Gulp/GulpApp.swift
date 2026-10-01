//
//  GulpApp.swift
//  Gulp
//

import SwiftUI
import UserNotifications

struct AboutCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("About Gulp") {
            openWindow(id: "about")
        }
    }
}

@main
struct GulpApp: App {
    @State private var uiState = UIState()
    @State private var settings = UserSettings()
    @State private var historyManager = HistoryManager()
    @State private var runner = GalleryDLRunner()

    init() {
        // Ensure config exists on launch
        ConfigManager.ensureConfigExists()

        // Request notification permissions
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    var body: some Scene {
        WindowGroup {
            FeedView()
                .frame(minWidth: 460, minHeight: 380)
                .environment(uiState)
                .environment(settings)
                .environment(historyManager)
                .environment(runner)
        }
        // The input bar is the title bar, so the title strip is hidden and the
        // traffic lights sit over the bar's leading inset.
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 620, height: 620)
        .commands {
            // The live row has a stop button, but a running download should also be
            // stoppable without finding it in the list.
            CommandGroup(replacing: .newItem) {
                Button("Stop Download") { runner.cancel() }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(!uiState.isDownloading)
            }
            CommandGroup(replacing: .appInfo) {
                AboutCommand()
            }
        }

        #if os(macOS)
        Window("About Gulp", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        #endif
    }
}
