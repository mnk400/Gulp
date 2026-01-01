<img src="Assets/gulp.png" alt="Gulp Icon" width="100"/>

# Gulp

A simple macOS app for [gallery-dl](https://github.com/mikf/gallery-dl) with history and log management.

<img src="Assets/ui.png" alt="Gulp UI" width="600"/>

## Installation

### Download
1. Download the latest `.dmg` from [Releases](../../releases)
2. Open the `.dmg` and drag Gulp to Applications
3. Install gallery-dl: `brew install gallery-dl`

> **Note:** The app is not notarized(I do not have an apple developer license), so macOS will show a warning on first launch. Right-click the app and select "Open" to bypass this or run `xattr -cr /Applications/Gulp.app` in the terminal before opening the app.

### Build from Source
1. Clone the repository
2. Open `Gulp.xcodeproj` in Xcode
3. Build and run (⌘R)

## Requirements

- macOS 26+
- [gallery-dl](https://github.com/mikf/gallery-dl) (`brew install gallery-dl`)

## Features

- Paste a URL and download with one click
- View download history and logs
- Supports all sites that gallery-dl supports
- App managed instance of gallery-dl's config.json

## License

MIT
