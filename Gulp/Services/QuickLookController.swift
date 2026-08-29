//
//  QuickLookController.swift
//  Gulp
//
//  Browsing downloaded files is handed to Quick Look rather than rebuilt in the
//  window. Previews the run's actual files, not its folder — Quick Look on a
//  directory only shows a folder icon.
//

import AppKit
import QuickLookUI

@MainActor
final class QuickLookController: NSObject {
    static let shared = QuickLookController()

    private var urls: [URL] = []

    /// Files a run put on disk, in the order gallery-dl reported them. Skipped files
    /// are included because they exist too — they were downloaded by an earlier run.
    static func previewableFiles(for run: DownloadRun) -> [URL] {
        run.logs
            .filter { $0.type == .download || $0.type == .skip }
            .map { $0.message.hasPrefix("# ") ? String($0.message.dropFirst(2)) : $0.message }
            .filter { $0.hasPrefix("/") }
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Returns false when a run has nothing left on disk, so the caller can say so
    /// instead of flashing an empty panel.
    @discardableResult
    func present(_ run: DownloadRun) -> Bool {
        let files = Self.previewableFiles(for: run)
        guard !files.isEmpty, let panel = QLPreviewPanel.shared() else { return false }

        urls = files
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
        return true
    }
}

extension QuickLookController: QLPreviewPanelDataSource {
    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { urls.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated {
            guard urls.indices.contains(index) else { return nil }
            return urls[index] as NSURL
        }
    }
}

extension QuickLookController: QLPreviewPanelDelegate {}
