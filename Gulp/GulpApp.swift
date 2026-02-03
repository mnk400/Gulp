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
            MainView()
                .environment(uiState)
                .environment(settings)
                .environment(historyManager)
                .environment(runner)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 800, height: 500)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .appInfo) {
                AboutCommand()
            }
        }

        #if os(macOS)
        Settings {
            SettingsView()
        }

        Window("About Gulp", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        #endif
    }
}
