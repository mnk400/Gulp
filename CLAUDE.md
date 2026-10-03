# Claude.md

## Overview
Gulp is a macOS GUI wrapper for gallery-dl: one window with a link field that doubles as the title bar, a feed of past downloads, and a footer holding the destination and a settings popover.

## Architecture
```
Gulp/
├── Models/
│   ├── UIState.swift          # Transient state for the live run (@Observable)
│   ├── UserSettings.swift     # Preferences, stored and written through to UserDefaults
│   └── DownloadRun.swift      # History entry; titles, failure summaries, file paths
├── Services/
│   ├── GalleryDLRunner.swift  # Runs gallery-dl, reads its output, settles the run
│   ├── HistoryManager.swift   # history.json persistence
│   ├── ConfigManager.swift    # Gulp's own gallery-dl config file
│   └── QuickLookController.swift
├── Views/
│   ├── FeedView.swift         # The whole window: input bar, feed, footer, keyboard model
│   ├── RunRowView.swift       # One row per run; the live run grows a third line
│   ├── FaviconView.swift
│   ├── Styles.swift           # Shared button styles and the live-run pulse
│   └── AboutView.swift
└── GulpApp.swift              # AppDelegate owns the shared state; asks before quitting mid-download
```

## Key Patterns
- **@Observable** for state (not ObservableObject), injected through the environment.
- **One download at a time.** The runner's counters live in `UIState`; a second run would take them over.
- **Failures belong on the row.** Only problems that leave no row (gallery-dl missing, unusable folder) raise an alert.
- **Schema versioning** in history.json. New optional fields decode from old files without a version bump.

## gallery-dl behaviour the code depends on
- File paths go to **stdout** (`/path` saved, `# /path` skipped); log messages go to **stderr**.
- Piped stderr carries severity **only as ANSI colour** (31 error, 33 warning). There is no `[error]` tag, so don't classify by text.
- Exit statuses are a **bitmask**, not signals. A run fails over a single file, so failed runs can still have saved files.
- `--no-skip` also disables any `--download-archive`. Skipping by file on disk is the default.
- gallery-dl prints nothing while one large file downloads, so a long silence isn't a stall.

## Build and run
```bash
open Gulp.xcodeproj   # ⌘R
```
Requires macOS 26+ and gallery-dl (`brew install gallery-dl`).

To try downloads without touching the real destination, launch with an argument override:
`open -n <Gulp.app> --args -outputDirectory /tmp/gulp-test`

History and config live in `~/Library/Application Support/GalleryDL/`.

## Releases
Pushing to `main` runs `.github/workflows/release.yml`. It bumps the patch version, writes the CHANGELOG from commit subjects, and publishes. Keep commit subjects readable as changelog lines.
