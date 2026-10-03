# Changelog

## [0.2.1] - 2026-10-03

### Changes
- chore(runner): Make preflight private
- fix(ui): Move the field to the column edge in full screen
- docs: Add CLAUDE.md for the redesigned app
- docs(readme): New screenshot, features, and keyboard shortcuts
- chore: Version 0.2.0 for the redesign
- refactor(runner): Start downloads synchronously and settle failed launches
- chore: Remove unused statusColor and updateBaseDirectory
- refactor(ui): Leave the destination to the footer
- refactor(settings): Keep preferences in one observable place
- fix(ui): Don't blame the server for a long silence
- fix(model): Title runs by their real common folder, and direct links by file name
- fix(ui): Stop offering a clipboard link that's already downloaded
- fix(ui): Trim typed links, and retry without touching the field
- fix(config): Drop the 1 MB/s download cap from the default config
- fix(history): Save at most once a second during a run, atomically, and keep unreadable files
- fix(runner): Stream both pipes as lines arrive
- feat(ui): Show what a failed run saved, and why a file failed
- fix(runner): Read stdout and stderr apart and classify log lines by colour
- fix(ui): Report a missing gallery-dl or unusable folder instead of dropping the link
- fix(app): Ask before quitting mid-download, and settle interrupted runs
- fix(runner): Make Skip existing files skip, not overwrite
- feat(ui): Show field focus through the placeholder and ⏎ offer
- fix(ui): Translucent unfocused selection, cleared when the field takes focus
- feat(model): Plain-language HTTP failure reasons
- fix(ui): Make Delete remove the selected download
- feat(ui): Finder-style destination and a tidier settings popover
- feat(ui): Warmer empty state
- feat(ui): Title bar and footer float over a fading feed
- fix(ui): Allow one download at a time
- feat(ui): Refine rows, live state, and stopping a run
- fix(ui): Let held arrow keys keep moving the selection
- fix(ui): Keep the traffic lights inset after a resize
- feat(ui): Shared favicon fetches with a consistent edge
- chore: Add the AccentColor asset
- feat(model): Readable failure reasons and bare-URL titles
- fix(model): Strip the skip prefix before finding a run's folder
- fix(runner): Only a signal counts as a cancel
- feat(ui): Glass marks the running row, not the input field
- refactor(ui): Fold LogDetailView into failed rows and delete the old shell
- feat(ui): Fold settings into a footer gear popover
- feat(ui): Selection and the keyboard model
- fix(ui): Translucent window and evenly inset traffic lights
- feat(ui): Ledger feed shell replacing the sidebar navigation
- Updating UI screenshot


## [0.1.11] - 2026-02-08

### Changes
- feat: Copy logs button in LogsView
- feat: Keyboard delete support for history sidebar
- fix(cancellation): More intense process cancellation, and fixing a bug where processes didn't cancel after switching views


## [0.1.10] - 2026-01-31

### Changes
- fix(parsing): Rewrite gallery-dl output parser to correctly detect files, skips, and errors File detection now uses hasPrefix("/") instead of contains("/") which was misclassifying stderr lines as downloads. Adds skip tracking, removes dead [n/N] progress code, fixes pipe read race condition on process exit, and closes pipe on cancel to unblock the reader.
- feat(debugging): Information about long running no feedback gallery-dl runs, and better run cancellation support for when child processes are spawned


## [0.1.9] - 2026-01-10

### Changes
- chore: An about view and adding a path filter for github workflow


## [0.1.8] - 2026-01-10

### Changes
- chore(readme): Updating screenshots


## [0.1.7] - 2026-01-05

### Changes
- chore(logs): Tweaking logs colors


## [0.1.6] - 2026-01-04

### Changes
- feat(sidebar): Button to open up gallery-dl config in the sidebar
- feat(errors): Adding a guidance section for failed/errored download runs, cleaning up ANSI from logs, adding a "View Logs" button to the error pop-ups
- chore(config): Adding guidance to the default config


## [0.1.5] - 2026-01-04

### Changes
- feat(sidebar): Show website favicons in the sidebar, minor tweaks to UI elements.


## [0.1.4] - 2026-01-04

### Changes
- Adding a retry button in the logs view for failed download attempts
- fix(padding): Fix minor padding issues in Logs and Download view


## [0.1.3] - 2026-01-03

### Changes
- feat(logs): Update the "Open in finder" button to open the deepest common directory, and update button styling



## [0.1.2] - 2026-01-03

### Changes
- Updating README with new brew installation instructions.



## [0.1.1] - 2026-01-03

### Changes
- Add automated release workflow



## [0.1.0] - 2025-01-01

### Added
- Initial release
- Download media from any gallery-dl supported site
- Download history with date grouping
- Detailed logs for each download
- Context menu actions (Open in Finder, Copy URL, Delete)
- Configurable output directory
- Skip existing files option
- Save metadata option
- Desktop notifications on completion
- Direct access to gallery-dl config file
