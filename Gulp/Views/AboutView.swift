//
//  AboutView.swift
//  Gulp
//

import SwiftUI

struct AboutView: View {
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)

            Text("Gulp")
                .font(.title)
                .fontWeight(.semibold)

            Text("Version \(appVersion) (\(buildNumber))")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("A macOS GUI for gallery-dl")
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider()
                .frame(width: 200)

            HStack(spacing: 20) {
                Link(destination: URL(string: "https://manik.cc")!) {
                    Label("Built by Manik", systemImage: "globe")
                }

                Link(destination: URL(string: "https://github.com/mnk400/Gulp")!) {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }
            .font(.callout)

            Spacer()
                .frame(height: 2)

            Text("\u{00A9} 2025 Manik. All rights reserved.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(width: 300, height: 350)
    }
}

#Preview {
    AboutView()
}
