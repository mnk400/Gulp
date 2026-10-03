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

/// Owns the app's shared state so the quit check and the window see the same
/// runner and history.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let uiState = UIState()
    let settings = UserSettings()
    let historyManager = HistoryManager()
    let runner = GalleryDLRunner()

    /// gallery-dl isn't a child that dies with us; quitting mid-download would
    /// leave it running unseen and the run stuck "in progress", so ask first.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard runner.isRunning else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = "A download is in progress"
        alert.informativeText = "Quitting stops it. Files already downloaded are kept."
        alert.addButton(withTitle: "Stop and Quit")
        alert.addButton(withTitle: "Cancel")

        // The window may be closed while the download carries on; then there's
        // nothing to attach a sheet to.
        guard let window = sender.windows.first(where: { $0.isVisible && $0.canBecomeMain }) else {
            guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
            stopForQuit()
            return .terminateNow
        }
        alert.beginSheetModal(for: window) { response in
            let quits = response == .alertFirstButtonReturn
            if quits { self.stopForQuit() }
            sender.reply(toApplicationShouldTerminate: quits)
        }
        return .terminateLater
    }

    private func stopForQuit() {
        runner.stopNow()
        historyManager.settleInterruptedRuns()
    }
}

@main
struct GulpApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

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
                .environment(appDelegate.uiState)
                .environment(appDelegate.settings)
                .environment(appDelegate.historyManager)
                .environment(appDelegate.runner)
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
                Button("Stop Download") { appDelegate.runner.cancel() }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(!appDelegate.uiState.isDownloading)
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
