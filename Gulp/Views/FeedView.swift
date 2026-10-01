//
//  FeedView.swift
//  Gulp
//
//  The whole app: an input bar that doubles as the title bar, a feed of runs,
//  and a footer. No sidebar, no detail views, no navigation.
//

import SwiftUI
import AppKit
import Combine

struct FeedView: View {
    @Environment(UIState.self) private var uiState
    @Environment(UserSettings.self) private var settings
    @Environment(HistoryManager.self) private var historyManager
    @Environment(GalleryDLRunner.self) private var runner
    @Environment(\.openWindow) private var openWindow

    @AppStorage("skipExisting") private var skipExisting = true
    @AppStorage("saveMetadata") private var saveMetadata = false
    @AppStorage("showNotifications") private var showNotifications = true
    @AppStorage("outputDirectory") private var outputDirectoryPath = ""

    @State private var selection: UUID?
    @State private var expandedLogs: Set<UUID> = []
    @State private var scrollTarget: UUID?
    @State private var stallMessage: String?
    @State private var clipboardSuggestion: String?
    @State private var showSettings = false
    /// Cached: the body re-runs for every line gallery-dl prints, and the
    /// display-name lookup goes to the filesystem.
    @State private var displayPath = ""
    @State private var showError = false
    @State private var errorMessage = ""

    private enum Focus { case field, feed }
    @FocusState private var focus: Focus?

    private let activityTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    // Leaves room for the traffic lights, which AppKit draws over our content once
    // the title bar is hidden. The cluster is inset 26pt so the corner reads evenly
    // and spans ~59pt; the 20pt gap after it has to be clearly wider than the gaps
    // inside it, or whatever comes next reads as a fourth light.
    private let lightsInset: CGFloat = 105

    var body: some View {
        @Bindable var uiState = uiState

        // The bars sit over the feed rather than beside it, so rows fade out
        // beneath them through the system's soft scroll-edge effect instead of
        // meeting a hard divider. At rest nothing is underneath and the window
        // reads as one surface.
        feed
            .safeAreaBar(edge: .top, spacing: 0) { inputBar(uiState: uiState) }
            .safeAreaBar(edge: .bottom, spacing: 0) { footer }
            .scrollEdgeEffectStyle(.soft, for: .vertical)
            .animation(.spring(response: 0.42, dampingFraction: 0.82), value: uiState.isDownloading)
        // A window can't spend Escape on dismissal the way a panel can, so it
        // unwinds the field and then the selection instead.
        .onExitCommand {
            if !uiState.url.isEmpty {
                uiState.url = ""
            } else if selection != nil {
                selection = nil
            } else {
                focus = .field
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .containerBackground(.ultraThinMaterial, for: .window)
        .background(WindowConfigurator(barHeight: 64))
        .onReceive(activityTimer) { _ in updateStallMessage() }
        .onChange(of: outputDirectoryPath, initial: true) {
            displayPath = Self.displayPath(for: settings.outputDirectory.path)
        }
        // Re-read on focus so a link copied while Gulp is already open still gets offered.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            readClipboard()
        }
        .onChange(of: uiState.isDownloading) { _, isDownloading in
            if !isDownloading { stallMessage = nil }
        }
        .onAppear {
            readClipboard()
            if GalleryDLRunner.findExecutable() == nil {
                errorMessage = "gallery-dl is not installed.\n\nInstall it with Homebrew:\nbrew install gallery-dl"
                showError = true
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Input bar (this is the title bar)

    private func inputBar(@Bindable uiState: UIState) -> some View {
        HStack(spacing: 12) {
            ZStack(alignment: .leading) {
                if uiState.url.isEmpty {
                    placeholder
                }
                TextField("", text: $uiState.url)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15.5))
                    .focused($focus, equals: .field)
                    .onSubmit(startDownload)
                    .onKeyPress(.downArrow) {
                        guard let first = historyManager.runs.first else { return .ignored }
                        if selection == nil { selection = first.id }
                        focus = .feed
                        return .handled
                    }
            }

            // Typing replaces the placeholder's offer, so the key that acts on
            // the field moves to the end of it.
            if !uiState.url.isEmpty {
                ReturnKeycap()
                    .transition(.blurReplace)
            }
        }
        .animation(.snappy(duration: 0.2), value: uiState.url.isEmpty)
        .padding(.leading, lightsInset)
        .padding(.trailing, 20)
        .frame(height: 64)
    }

    /// When the pasteboard holds a URL the placeholder becomes an offer, which is
    /// why there's no paste button.
    @ViewBuilder
    private var placeholder: some View {
        HStack(spacing: 8) {
            if let suggestion = clipboardSuggestion {
                ReturnKeycap()
                Text("to download \(Text(shortened(suggestion)).foregroundStyle(.secondary))")
            } else {
                Text("Paste a gallery or image link…")
            }
        }
        .font(.system(size: 15.5))
        .foregroundStyle(.tertiary)
        .lineLimit(1)
        .allowsHitTesting(false)
    }

    private func shortened(_ url: String) -> String {
        let bare = url.replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        return bare.count > 52 ? bare.prefix(51) + "…" : bare
    }

    // MARK: - Feed

    @ViewBuilder
    private var feed: some View {
        if historyManager.runs.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(historyManager.runs) { run in
                            RunRowView(
                                run: run,
                                live: liveStats(for: run),
                                isSelected: selection == run.id,
                                isFocused: focus == .feed,
                                isLogExpanded: expandedLogs.contains(run.id),
                                onToggleLog: { toggleLog(run) },
                                onRetry: { retry(run) },
                                onStop: { runner.cancel() },
                                onSelect: { select(run) },
                                onOpen: { revealInFinder(run) }
                            )
                            .id(run.id)
                            // Clicks outside the row's own lines (around an open log)
                            // still select it.
                            .onTapGesture { select(run) }
                            .contextMenu { menu(for: run) }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    // Keyed on the count: the body re-runs for every line gallery-dl
                    // prints, and an id array would be rebuilt on each of them.
                    .animation(.snappy(duration: 0.3), value: historyManager.runs.count)
                    .animation(.snappy(duration: 0.25), value: expandedLogs)
                }
                // With the bars floating over the feed, the scroll view otherwise
                // opens partway down the list.
                .defaultScrollAnchor(.top)
                .onChange(of: selection) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id) }
                }
                // An expanding log on a low row would otherwise push its own
                // guidance links out of sight.
                .onChange(of: scrollTarget) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(id, anchor: .bottom) }
                    scrollTarget = nil
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .focusable()
            .focusEffectDisabled()
            .focused($focus, equals: .feed)
            // Holding a key delivers `.repeat`, not `.down`; without it a held
            // arrow moved one row and stopped.
            .onKeyPress(phases: [.down, .repeat]) { press in handle(press) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .padding(.bottom, 14)
            Text("Nothing downloaded yet")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 5)
            Text("Paste a gallery or image link above. Anything gallery-dl supports works here.")
                .font(.system(size: 12.5))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 280)
                .padding(.bottom, 10)
            Button("Supported Sites") {
                NSWorkspace.shared.open(URL(string: "https://github.com/mikf/gallery-dl/blob/master/docs/supportedsites.md")!)
            }
            .buttonStyle(HoverHighlightButtonStyle())
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.accentColor)
        }
        // Sits a little above centre, where the eye lands in an empty window.
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Live values belong to whichever run is currently active.
    private func liveStats(for run: DownloadRun) -> LiveStats? {
        guard uiState.isDownloading, uiState.currentRunId == run.id else { return nil }
        return LiveStats(
            fileCount: uiState.downloadedCount,
            skippedCount: uiState.skippedCount,
            sizeText: uiState.totalBytes > 0
                ? ByteCountFormatter.string(fromByteCount: uiState.totalBytes, countStyle: .file)
                : nil,
            rateText: uiState.bytesPerSecond > 0 ? uiState.rateText : nil,
            currentFile: uiState.currentFile,
            stallMessage: stallMessage
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 4) {
            Menu {
                Button("Open in Finder") { NSWorkspace.shared.open(settings.outputDirectory) }
                Button("Choose Destination…") { chooseDestination() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                    Text(displayPath)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(HoverHighlightButtonStyle())
            .fixedSize(horizontal: false, vertical: true)
            .help("Downloads are saved here")

            Spacer(minLength: 8)

            Button {
                showSettings.toggle()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(HoverHighlightButtonStyle())
            .help("Settings")
            .popover(isPresented: $showSettings, arrowEdge: .top) {
                settingsPopover
            }
        }
        // The controls carry their own 7pt hover inset, so the edges sit 7pt in
        // from the ledger's 16pt column.
        .padding(.horizontal, 9)
        .frame(height: 38)
    }

    /// Four preferences and two links, which is all the old Settings scene held.
    private var settingsPopover: some View {
        let isInstalled = GalleryDLRunner.findExecutable() != nil

        return VStack(alignment: .leading, spacing: 0) {
            popoverHeader("Downloads")

            VStack(spacing: 8) {
                settingToggle("Skip existing files", $skipExisting)
                settingToggle("Save metadata", $saveMetadata)
                settingToggle("Notify when finished", $showNotifications)
            }
            .padding(.horizontal, 7)

            popoverDivider

            popoverHeader("Save to")

            Button(action: chooseDestination) {
                HStack(spacing: 7) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(Color.accentColor)
                    Text(displayPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text("Change…")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(HoverHighlightButtonStyle(fillsWidth: true))

            popoverDivider

            HStack(spacing: 7) {
                Circle()
                    .fill(isInstalled ? Color.green : .red)
                    .frame(width: 7, height: 7)
                Text(isInstalled ? "gallery-dl installed" : "gallery-dl not found")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if isInstalled {
                    Button("Edit Config…") { ConfigManager.openInEditor() }
                        .buttonStyle(HoverHighlightButtonStyle())
                        .foregroundStyle(Color.accentColor)
                        .padding(.trailing, -7)
                }
            }
            .padding(.horizontal, 7)
            .frame(minHeight: 24)

            if !isInstalled {
                Text("Install it with `brew install gallery-dl`")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 7)
                    .padding(.top, 2)
            }

            popoverDivider

            Button("About Gulp") {
                showSettings = false
                openWindow(id: "about")
            }
            .buttonStyle(HoverHighlightButtonStyle(fillsWidth: true))
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .font(.system(size: 12.5))
        .padding(9)
        .frame(width: 300)
    }

    private func popoverHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.top, 2)
            .padding(.bottom, 7)
    }

    private var popoverDivider: some View {
        Divider()
            .padding(.horizontal, 7)
            .padding(.vertical, 8)
    }

    /// Switch-style toggles right-align their own label outside a Form, so the row
    /// is laid out explicitly instead.
    private func settingToggle(_ title: String, _ isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 0)
            Toggle(title, isOn: isOn).labelsHidden()
        }
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose where to save downloads"
        panel.directoryURL = settings.outputDirectory

        if panel.runModal() == .OK, let url = panel.url {
            outputDirectoryPath = url.path
        }
    }

    /// Paths the way Finder names them. iCloud Drive lives under a path nobody
    /// should have to read (`~/Library/Mobile Documents/com~apple~CloudDocs`), so
    /// those are shown by display name; everything else keeps the familiar `~/`.
    private static func displayPath(for path: String) -> String {
        if path.contains("/Library/Mobile Documents/"),
           let components = FileManager.default.componentsToDisplay(forPath: path),
           let drive = components.firstIndex(of: "iCloud Drive") {
            return components[drive...].joined(separator: " › ")
        }
        return path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    // MARK: - Keyboard

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        if press.modifiers.contains(.command) {
            guard press.characters == "c", let run = selectedRun else { return .ignored }
            copyURL(run)
            return .handled
        }

        // Only movement repeats. A held Space or Return would reopen Quick Look or
        // Finder on every tick, and a held Delete would eat the history.
        let isRepeat = press.phase == .repeat
        let actsOnce: Set<KeyEquivalent> = [.space, .return, .delete, .deleteForward]
        if isRepeat && actsOnce.contains(press.key) {
            return .handled
        }

        switch press.key {
        case .upArrow:
            // Leaving the top of the list hands focus back to the field — but only
            // on a fresh press, so holding the key stops at the first row.
            if selection == historyManager.runs.first?.id {
                guard !isRepeat else { return .handled }
                selection = nil
                focus = .field
            } else {
                moveSelection(by: -1)
            }
            return .handled

        case .downArrow:
            moveSelection(by: 1)
            return .handled

        case .space:
            if let run = selectedRun { quickLook(run) }
            return .handled

        case .return:
            if let run = selectedRun { revealInFinder(run) }
            return .handled

        case .delete, .deleteForward:
            if let run = selectedRun { delete(run) }
            return .handled

        default:
            return .ignored
        }
    }

    private var selectedRun: DownloadRun? {
        historyManager.runs.first { $0.id == selection }
    }

    private func moveSelection(by offset: Int) {
        let runs = historyManager.runs
        guard !runs.isEmpty else { return }
        guard let current = runs.firstIndex(where: { $0.id == selection }) else {
            selection = runs.first?.id
            return
        }
        let next = min(runs.count - 1, max(0, current + offset))
        selection = runs[next].id
    }

    // MARK: - Row commands

    @ViewBuilder
    private func menu(for run: DownloadRun) -> some View {
        Button("Quick Look") { quickLook(run) }
        Button("Open in Finder") { revealInFinder(run) }
        Button("Copy Link") { copyURL(run) }
        if run.status == .failed {
            Button("Retry") { retry(run) }
            Button(expandedLogs.contains(run.id) ? "Hide Log" : "Show Log") { toggleLog(run) }
        }
        Button("Copy Logs") { copyLogs(run) }
        Divider()
        if isLive(run) {
            Button("Stop Download") { runner.cancel() }
        } else {
            Button("Delete", role: .destructive) { delete(run) }
        }
    }

    private func quickLook(_ run: DownloadRun) {
        if !QuickLookController.shared.present(run) {
            errorMessage = "Nothing to preview — this run's files are no longer on disk."
            showError = true
        }
    }

    private func revealInFinder(_ run: DownloadRun) {
        let directory = URL(fileURLWithPath: run.actualDownloadDirectory)
        let target = FileManager.default.fileExists(atPath: directory.path)
            ? directory
            : URL(fileURLWithPath: run.outputDirectory)
        NSWorkspace.shared.open(target)
    }

    private func copyURL(_ run: DownloadRun) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(run.url, forType: .string)
    }

    private func copyLogs(_ run: DownloadRun) {
        let text = run.logs
            .map { "[\($0.timestamp.formatted(date: .omitted, time: .standard))] \($0.message)" }
            .joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func isLive(_ run: DownloadRun) -> Bool {
        uiState.isDownloading && uiState.currentRunId == run.id
    }

    private func select(_ run: DownloadRun) {
        selection = run.id
        focus = .feed
    }

    private func delete(_ run: DownloadRun) {
        // Deleting the live row would hide a download that keeps running with no
        // row left to stop it from. Stopping comes first.
        guard !isLive(run) else {
            NSSound.beep()
            return
        }

        let runs = historyManager.runs
        let index = runs.firstIndex { $0.id == run.id }
        historyManager.deleteRun(run)
        expandedLogs.remove(run.id)

        // Keep the selection on a neighbour so the list stays keyboard-navigable.
        let remaining = historyManager.runs
        if let index, !remaining.isEmpty {
            selection = remaining[min(index, remaining.count - 1)].id
        } else {
            selection = nil
        }
    }

    // MARK: - Actions

    private func toggleLog(_ run: DownloadRun) {
        if expandedLogs.contains(run.id) {
            expandedLogs.remove(run.id)
        } else {
            expandedLogs.insert(run.id)
            scrollTarget = run.id
        }
    }

    private func retry(_ run: DownloadRun) {
        uiState.url = run.url
        startDownload()
    }

    /// Only offers something that is unambiguously a link — an explicit http(s)
    /// scheme and a dotted host. Anything looser turns arbitrary copied text into
    /// a download the user only has to press Return to start.
    private func readClipboard() {
        clipboardSuggestion = nil

        guard let raw = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty, raw.count < 2048,
              !raw.contains(where: \.isWhitespace),
              let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, host.contains(".")
        else { return }

        clipboardSuggestion = raw
    }

    private func startDownload() {
        // An empty field accepts the clipboard suggestion the placeholder offered.
        if uiState.url.isEmpty, let suggestion = clipboardSuggestion {
            uiState.url = suggestion
        }
        guard !uiState.url.isEmpty else { return }

        // The runner drives one process at a time: a second run would take over
        // the first one's counters and leave it orphaned and unstoppable. The
        // link stays in the field to start once this one is done.
        guard !uiState.isDownloading else {
            NSSound.beep()
            return
        }

        let url = uiState.url
        uiState.url = ""
        clipboardSuggestion = nil

        Task {
            do {
                try await runner.run(url: url,
                                     outputDir: settings.outputDirectory,
                                     uiState: uiState,
                                     settings: settings,
                                     historyManager: historyManager)
            } catch GalleryDLError.cancelled {
                // Cancelling is not an error; the row already says so.
            } catch {
                // The failed row carries the detail, so the alert stays quiet.
                errorMessage = error.localizedDescription
            }
        }
    }

    private func updateStallMessage() {
        guard uiState.isDownloading, let last = uiState.lastActivityTime else {
            stallMessage = nil
            return
        }
        let elapsed = Int(Date().timeIntervalSince(last))
        if elapsed > 30 {
            stallMessage = "waiting \(elapsed)s — the server may be throttling"
        } else if elapsed > 10 {
            stallMessage = "waiting \(elapsed)s"
        } else {
            stallMessage = nil
        }
    }
}

/// The key that acts on the field, drawn as a keycap so it reads as a key and
/// not as text.
private struct ReturnKeycap: View {
    var body: some View {
        Text("⏎")
            .font(.system(size: 10.5, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.15),
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .foregroundStyle(Color.accentColor)
    }
}

#Preview {
    FeedView()
        .environment(UIState())
        .environment(UserSettings())
        .environment(HistoryManager())
        .environment(GalleryDLRunner())
        .frame(width: 620, height: 620)
}


/// The input bar replaces the title bar, which leaves two AppKit problems:
/// a text field swallows the clicks a title bar would treat as drags, and the
/// traffic lights stay pinned to the standard 28pt title bar rather than
/// centring in our taller bar. Both are fixed on the window itself.
private struct WindowConfigurator: NSViewRepresentable {
    let barHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(barHeight: barHeight)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { context.coordinator.attach(to: view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { context.coordinator.attach(to: nsView.window) }
    }

    /// AppKit lays the title bar out again on every resize and puts the buttons
    /// back where it thinks they belong, so moving them once isn't enough: the
    /// coordinator watches for anything that resets them and moves them back.
    @MainActor
    final class Coordinator {
        private let barHeight: CGFloat
        private weak var window: NSWindow?
        nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

        init(barHeight: CGFloat) {
            self.barHeight = barHeight
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }

        func attach(to window: NSWindow?) {
            guard let window else { return }
            if window !== self.window {
                self.window = window
                observe(window)
            }
            // Lets the whole background drag the window, so the field can keep the bar.
            window.isMovableByWindowBackground = true
            repositionLights()
        }

        private func observe(_ window: NSWindow) {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []

            // A nil queue runs the handler synchronously as AppKit posts, so a
            // reset button is moved back before the frame is drawn — an async hop
            // shows it jumping to the corner and back during a live resize.
            func watch(_ name: Notification.Name, of object: AnyObject) {
                observers.append(NotificationCenter.default.addObserver(
                    forName: name, object: object, queue: nil
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.repositionLights() }
                })
            }

            watch(NSWindow.didResizeNotification, of: window)
            watch(NSWindow.didExitFullScreenNotification, of: window)

            if let close = window.standardWindowButton(.closeButton) {
                close.postsFrameChangedNotifications = true
                watch(NSView.frameDidChangeNotification, of: close)
            }
        }

        private func repositionLights() {
            guard let window,
                  // Full screen shows the lights in its own reveal strip, which
                  // our bar's geometry has nothing to do with.
                  !window.styleMask.contains(.fullScreen),
                  let close = window.standardWindowButton(.closeButton),
                  let titlebar = close.superview else { return }

            // The cluster would otherwise sit centred in the standard 28pt title bar,
            // near the top of our taller one. Moving it down means a negative y in the
            // unflipped titlebar view, so that view must stop clipping first.
            titlebar.wantsLayer = true
            titlebar.layer?.masksToBounds = false
            titlebar.superview?.wantsLayer = true
            titlebar.superview?.layer?.masksToBounds = false

            // Inset equally from the top and leading edges. Shifting by a delta rather
            // than assigning absolute x keeps the cluster's own spacing intact.
            let inset = (barHeight - close.frame.height) / 2
            let dx = inset - close.frame.origin.x
            let y = titlebar.frame.height - barHeight / 2 - close.frame.height / 2

            // Already in place: return before touching any frame, or moving the
            // close button would re-post the very notification that called this.
            guard abs(dx) > 0.5 || abs(close.frame.origin.y - y) > 0.5 else { return }

            for button in [close,
                           window.standardWindowButton(.miniaturizeButton),
                           window.standardWindowButton(.zoomButton)].compactMap({ $0 }) {
                button.setFrameOrigin(NSPoint(x: button.frame.origin.x + dx, y: y))
            }
        }
    }
}
