//
//  FaviconView.swift
//  Gulp
//

import SwiftUI

struct FaviconView: View {
    let domain: String
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 16, height: 16)
        .task {
            await loadFavicon()
        }
    }

    private func loadFavicon() async {
        // Skip if already loaded or invalid domain
        guard image == nil, !domain.isEmpty else { return }

        guard let url = URL(string: "https://www.google.com/s2/favicons?domain=\(domain)&sz=32") else {
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let nsImage = NSImage(data: data) {
                self.image = nsImage
            }
        } catch {
            // Keep showing globe on error
        }
    }
}
