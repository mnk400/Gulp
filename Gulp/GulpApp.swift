//
//  GulpApp.swift
//  Gulp
//

import SwiftUI
import UserNotifications

@main
struct GulpApp: App {
    @State private var appState = AppState()
    @State private var historyManager = HistoryManager()

    init() {
        // Ensure config exists on launch
        ConfigManager.ensureConfigExists()

        // Request notification permissions
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(appState)
                .environment(historyManager)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 800, height: 500)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}
