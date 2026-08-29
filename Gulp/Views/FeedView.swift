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
    @Environment(\.openSettings) private var openSettings

    @State private var selection: UUID?
    @State private var expandedLogs: Set<UUID> = []
    @State private var stallMessage: String?
    @State private var clipboardSuggestion: String?
    @State private var showError = false
    @State private var errorMessage = ""

    @FocusState private var fieldFocused: Bool

    private let activityTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    // Leaves room for the traffic lights, which AppKit draws over our content once
    // the title bar is hidden. The cluster is inset by (barHeight - 12) / 2 = 26 on
    // both axes so the corner reads evenly, then spans 52pt, then a 12pt gap.
    private let lightsInset: CGFloat = 90

    var body: some View {
        @Bindable var uiState = uiState

        VStack(spacing: 0) {
            inputBar(uiState: uiState)
            Divider()
            feed
            Divider()
            footer
        }
        .ignoresSafeArea(.container, edges: .top)
        .containerBackground(.ultraThinMaterial, for: .window)
        .background(WindowConfigurator(barHeight: 64))
        .onReceive(activityTimer) { _ in updateStallMessage() }
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
            Image(systemName: "drop")
                .font(.system(size: 15))
                .foregroundStyle(.tertiary)

            ZStack(alignment: .leading) {
                if uiState.url.isEmpty {
                    placeholder
                }
                TextField("", text: $uiState.url)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15.5))
                    .focused($fieldFocused)
                    .onSubmit(startDownload)
            }
        }
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
                Text("⏎")
                    .font(.system(size: 10.5, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
                    .foregroundStyle(Color.accentColor)
                Text("to download \(shortened(suggestion))")
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
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(historyManager.runs) { run in
                        RunRowView(
                            run: run,
                            live: liveStats(for: run),
                            isSelected: selection == run.id,
                            isLogExpanded: expandedLogs.contains(run.id),
                            onToggleLog: { toggleLog(run) },
                            onRetry: { retry(run) }
                        )
                        .onTapGesture { selection = run.id }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "drop")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("Nothing downloaded yet")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Paste a gallery or image link above. Anything gallery-dl supports works here.")
                .font(.system(size: 12.5))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
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
            rateText: uiState.rateText,
            currentFile: uiState.currentFile,
            stallMessage: stallMessage
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                NSWorkspace.shared.open(settings.outputDirectory)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                    Text(displayPath)
                }
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
        .background(.quaternary.opacity(0.25))
    }

    private var displayPath: String {
        settings.outputDirectory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    // MARK: - Actions

    private func toggleLog(_ run: DownloadRun) {
        if expandedLogs.contains(run.id) {
            expandedLogs.remove(run.id)
        } else {
            expandedLogs.insert(run.id)
        }
    }

    private func retry(_ run: DownloadRun) {
        uiState.url = run.url
        fieldFocused = true
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

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }

        // Lets the whole background drag the window, so the field can keep the bar.
        window.isMovableByWindowBackground = true

        guard let close = window.standardWindowButton(.closeButton),
              let titlebar = close.superview else { return }

        // The cluster would otherwise sit centred in the standard 28pt title bar,
        // near the top of our taller one. Moving it down means a negative y in the
        // unflipped titlebar view, so that view must stop clipping first.
        titlebar.wantsLayer = true
        titlebar.layer?.masksToBounds = false
        titlebar.superview?.wantsLayer = true
        titlebar.superview?.layer?.masksToBounds = false

        // Inset equally from the top and leading edges. Shifting by a delta rather
        // than assigning absolute x keeps the cluster's own spacing intact and makes
        // repeated calls idempotent.
        let inset = (barHeight - close.frame.height) / 2
        let dx = inset - close.frame.origin.x
        let y = titlebar.frame.height - barHeight / 2 - close.frame.height / 2

        for button in [close,
                       window.standardWindowButton(.miniaturizeButton),
                       window.standardWindowButton(.zoomButton)].compactMap({ $0 }) {
            button.setFrameOrigin(NSPoint(x: button.frame.origin.x + dx, y: y))
        }
    }
}
