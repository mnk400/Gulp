//
//  GulpApp.swift
//  Gulp
//

import SwiftUI
import UserNotifications

@main
struct GulpApp: App {
    @State private var appState = AppState()

    init() {
        // Ensure config exists on launch
        ConfigManager.ensureConfigExists()

        // Request notification permissions
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 380, height: 200)
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
