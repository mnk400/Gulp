//
//  FaviconView.swift
//  Gulp
//

import SwiftUI

struct FaviconView: View {
    let domain: String
    /// The fallback globe is a tint, so it has to turn white on a selection
    /// like the row's text does; real icons are left as the site drew them.
    var isOnSelection = false
    @State private var image: NSImage?
    @Environment(\.colorScheme) private var colorScheme

    /// One fetch per domain, shared. Rows in a lazy stack are rebuilt as they
    /// scroll and many rows share a site, so without this every row fetched its
    /// own copy. A finished task is kept even when it found nothing, so domains
    /// Google has no icon for aren't asked about again on every scroll.
    @MainActor private static var fetches: [String: Task<NSImage?, Never>] = [:]
    /// Finished icons, readable synchronously so a rebuilt row draws its icon on
    /// the first frame instead of flashing the globe while its task resumes.
    @MainActor private static var icons: [String: NSImage] = [:]

    var body: some View {
        Group {
            if let image = image ?? Self.icons[domain] {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    // Sites ship square, round, and full-bleed icons; one shared
                    // corner keeps the leading column reading as a column.
                    .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                    // Dark icons vanish into a dark window (X's is black on black)
                    // without an edge of their own.
                    .overlay {
                        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                            .strokeBorder((colorScheme == .dark ? Color.white : .black).opacity(0.1),
                                          lineWidth: 0.5)
                    }
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 12.5))
                    .foregroundStyle(isOnSelection ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.tertiary))
            }
        }
        .frame(width: 16, height: 16)
        .task(id: domain) {
            await loadFavicon()
        }
    }

    private func loadFavicon() async {
        guard !domain.isEmpty, Self.icons[domain] == nil else { return }

        let fetch: Task<NSImage?, Never>
        if let existing = Self.fetches[domain] {
            fetch = existing
        } else {
            let domain = domain
            fetch = Task { await Self.fetchFavicon(for: domain) }
            Self.fetches[domain] = fetch
        }
        image = await fetch.value
    }

    @MainActor
    private static func fetchFavicon(for domain: String) async -> NSImage? {
        guard let url = URL(string: "https://www.google.com/s2/favicons?domain=\(domain)&sz=32") else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            // Unknown domains still get an image back — Google's blurry default
            // globe — but with a 404, which is the only way to tell it apart.
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let icon = NSImage(data: data) else { return nil }
            icons[domain] = icon
            return icon
        } catch {
            // Offline is not "no icon": forget the attempt so a later row retries.
            fetches[domain] = nil
            return nil
        }
    }
}
