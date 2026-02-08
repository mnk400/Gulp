# Changelog

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
