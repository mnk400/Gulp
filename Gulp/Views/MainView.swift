//
//  MainView.swift
//  Gulp
//

import SwiftUI

struct MainView: View {
    @Environment(AppState.self) private var state
    @Environment(HistoryManager.self) private var historyManager
    @State private var selection: NavigationItem? = .download

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            detailView
        }
        .frame(minWidth: 700, minHeight: 400)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .download, .none:
            DownloadView(selection: $selection)

        case .run(let id):
            if let run = historyManager.runs.first(where: { $0.id == id }) {
                LogDetailView(run: run)
            } else {
                ContentUnavailableView("Run Not Found", systemImage: "questionmark.folder")
            }
        }
    }
}

#Preview {
    MainView()
        .environment(AppState())
        .environment(HistoryManager())
}
